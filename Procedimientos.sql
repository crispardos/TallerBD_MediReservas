CREATE OR REPLACE PROCEDURE prc_registrar_paciente (
    p_email            IN VARCHAR2,
    p_password_hash    IN VARCHAR2,
    p_run              IN VARCHAR2,
    p_first_name       IN VARCHAR2,
    p_last_name        IN VARCHAR2,
    p_phone            IN VARCHAR2,
    p_birth_date       IN DATE,
    p_address          IN VARCHAR2,
    p_health_insurance IN VARCHAR2,
    p_emergency_name   IN VARCHAR2,
    p_emergency_phone  IN VARCHAR2,
    p_blood_type       IN VARCHAR2,
    p_allergies        IN VARCHAR2,
    p_weight           IN NUMBER,
    p_user_id          OUT NUMBER
)
IS
    v_auth_user_id NUMBER;
    v_existe       NUMBER;
BEGIN
    -- 1. Validar RUN
    IF fn_validar_run(p_run) = 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'RUN inválido: ' || p_run);
    END IF;

    -- 2. Verificar email duplicado en auth_users
    SELECT COUNT(*) INTO v_existe
    FROM auth_users
    WHERE email = p_email;

    IF v_existe > 0 THEN
        RAISE_APPLICATION_ERROR(-20002, 'Email ya registrado: ' || p_email);
    END IF;

    -- 3. Verificar RUN duplicado en users
    SELECT COUNT(*) INTO v_existe
    FROM users
    WHERE run = p_run;

    IF v_existe > 0 THEN
        RAISE_APPLICATION_ERROR(-20003, 'RUN ya registrado: ' || p_run);
    END IF;

    -- 4. Insertar auth_users
    INSERT INTO auth_users (email, password_hash, enabled, created_at)
    VALUES (p_email, p_password_hash, 1, SYSTIMESTAMP)
    RETURNING auth_user_id INTO v_auth_user_id;

    -- 5. Asignar rol PATIENT (role_id = 3)
    INSERT INTO auth_user_roles (auth_user_id, role_id)
    VALUES (v_auth_user_id, 3);

    -- 6. Insertar users
    INSERT INTO users (auth_user_id, run, email, active, created_at)
    VALUES (v_auth_user_id, p_run, p_email, 1, SYSTIMESTAMP)
    RETURNING user_id INTO p_user_id;

    -- 7. Insertar user_profiles
    INSERT INTO user_profiles (
        user_id, first_name, last_name, phone, birth_date, address
    ) VALUES (
        p_user_id, p_first_name, p_last_name, p_phone, p_birth_date, p_address
    );

    -- 8. Insertar patient_profiles
    INSERT INTO patient_profiles (
        user_id, health_insurance, emergency_contact_name,
        emergency_contact_phone, blood_type, allergies, weight
    ) VALUES (
        p_user_id, p_health_insurance, p_emergency_name,
        p_emergency_phone, p_blood_type, p_allergies, p_weight
    );

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END prc_registrar_paciente;
/
CREATE OR REPLACE PROCEDURE prc_agendar_cita (
    p_patient_user_id  IN NUMBER,
    p_doctor_id        IN NUMBER,
    p_specialty_id     IN NUMBER,
    p_schedule_slot_id IN NUMBER,
    p_reason           IN VARCHAR2,
    p_appointment_id   OUT NUMBER
)
IS
    v_existe         NUMBER;
    v_slot_estado    VARCHAR2(30);
    v_slot_fecha     DATE;
    v_atiende        NUMBER;
BEGIN
    -- 1. Verificar paciente activo
    SELECT COUNT(*) INTO v_existe
    FROM users u
    INNER JOIN patient_profiles pp ON u.user_id = pp.user_id
    WHERE u.user_id = p_patient_user_id
      AND u.active = 1;

    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20010, 'Paciente no existe o está inactivo');
    END IF;

    -- 2. Verificar doctor activo
    SELECT COUNT(*) INTO v_existe
    FROM doctors
    WHERE doctor_id = p_doctor_id
      AND active = 1;

    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20011, 'Doctor no existe o está inactivo');
    END IF;

    -- 3. Verificar slot disponible y en el futuro
    SELECT slot_status, slot_date
    INTO v_slot_estado, v_slot_fecha
    FROM schedule_slots
    WHERE schedule_slot_id = p_schedule_slot_id;

    IF v_slot_estado <> 'AVAILABLE' THEN
        RAISE_APPLICATION_ERROR(-20012, 'Slot no disponible. Estado actual: ' || v_slot_estado);
    END IF;

    IF v_slot_fecha < TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20013, 'Slot en fecha pasada');
    END IF;

    -- 4. Verificar que el doctor atienda esa especialidad
    SELECT COUNT(*) INTO v_atiende
    FROM doctor_specialties
    WHERE doctor_id = p_doctor_id
      AND specialty_id = p_specialty_id;

    IF v_atiende = 0 THEN
        RAISE_APPLICATION_ERROR(-20014, 'El doctor no atiende la especialidad indicada');
    END IF;

    -- 5. Verificar que el slot pertenezca a ese doctor
    SELECT COUNT(*) INTO v_existe
    FROM schedule_slots
    WHERE schedule_slot_id = p_schedule_slot_id
      AND doctor_id = p_doctor_id;

    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20015, 'El slot no pertenece al doctor indicado');
    END IF;

    -- 6. Insertar cita
    INSERT INTO appointments (
        patient_user_id, doctor_id, specialty_id,
        schedule_slot_id, appointment_status, reason, created_at
    ) VALUES (
        p_patient_user_id, p_doctor_id, p_specialty_id,
        p_schedule_slot_id, 'PENDING', p_reason, SYSTIMESTAMP
    ) RETURNING appointment_id INTO p_appointment_id;

    -- 7. Registrar historial inicial
    INSERT INTO appointment_status_history (
        appointment_id, old_status, new_status,
        changed_by_user_id, change_reason, changed_at
    ) VALUES (
        p_appointment_id, NULL, 'PENDING',
        p_patient_user_id, 'Registro de reserva', SYSTIMESTAMP
    );

    -- 8. Marcar slot como reservado
    UPDATE schedule_slots
    SET slot_status = 'BOOKED',
        appointment_id = p_appointment_id
    WHERE schedule_slot_id = p_schedule_slot_id;

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20016, 'Slot no encontrado: ' || p_schedule_slot_id);
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END prc_agendar_cita;
/
CREATE OR REPLACE PROCEDURE prc_cancelar_cita (
    p_appointment_id    IN NUMBER,
    p_cancelled_by_user IN NUMBER,
    p_reason            IN VARCHAR2
)
IS
    v_estado     VARCHAR2(30);
    v_slot_id    NUMBER;
    v_cancelable NUMBER;
BEGIN
    -- 1. Obtener estado y slot de la cita
    SELECT appointment_status, schedule_slot_id
    INTO v_estado, v_slot_id
    FROM appointments
    WHERE appointment_id = p_appointment_id;

    -- 2. Verificar que sea cancelable
    IF v_estado NOT IN ('PENDING', 'CONFIRMED') THEN
        RAISE_APPLICATION_ERROR(-20020, 'Cita no cancelable. Estado actual: ' || v_estado);
    END IF;

    -- 3. Actualizar estado de la cita
    UPDATE appointments
    SET appointment_status = 'CANCELLED'
    WHERE appointment_id = p_appointment_id;

    -- 4. Liberar slot
    UPDATE schedule_slots
    SET slot_status = 'AVAILABLE',
        appointment_id = NULL
    WHERE schedule_slot_id = v_slot_id;

    -- 5. Registrar cancelación
    INSERT INTO appointment_cancellations (
        appointment_id, cancelled_by_user_id, cancellation_reason, cancelled_at
    ) VALUES (
        p_appointment_id, p_cancelled_by_user, p_reason, SYSTIMESTAMP
    );

    -- 6. Registrar historial
    INSERT INTO appointment_status_history (
        appointment_id, old_status, new_status,
        changed_by_user_id, change_reason, changed_at
    ) VALUES (
        p_appointment_id, v_estado, 'CANCELLED',
        p_cancelled_by_user, p_reason, SYSTIMESTAMP
    );

    COMMIT;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        ROLLBACK;
        RAISE_APPLICATION_ERROR(-20021, 'Cita no encontrada: ' || p_appointment_id);
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END prc_cancelar_cita;
/
CREATE OR REPLACE PROCEDURE prc_registrar_pago (
    p_appointment_id  IN NUMBER,
    p_patient_user_id IN NUMBER,
    p_amount          IN NUMBER,
    p_payment_method  IN VARCHAR2,
    p_payment_id      OUT NUMBER
)
IS
    v_existe          NUMBER;
    v_tx_code         VARCHAR2(30);
    v_receipt_number  VARCHAR2(30);
BEGIN
    -- 1. Verificar que la cita exista
    SELECT COUNT(*) INTO v_existe
    FROM appointments
    WHERE appointment_id = p_appointment_id;

    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20030, 'Cita no existe: ' || p_appointment_id);
    END IF;

    -- 2. Verificar que no exista pago PAID previo
    SELECT COUNT(*) INTO v_existe
    FROM payments
    WHERE appointment_id = p_appointment_id
      AND payment_status = 'PAID';

    IF v_existe > 0 THEN
        RAISE_APPLICATION_ERROR(-20031, 'La cita ya tiene un pago confirmado');
    END IF;

    -- 3. Generar código de transacción
    v_tx_code := fn_generar_codigo('TX', 8);

    -- 4. Insertar pago
    INSERT INTO payments (
        appointment_id, patient_user_id, amount,
        payment_method, payment_status, transaction_code,
        paid_at, created_at
    ) VALUES (
        p_appointment_id, p_patient_user_id, p_amount,
        p_payment_method, 'PAID', v_tx_code,
        SYSTIMESTAMP, SYSTIMESTAMP
    ) RETURNING payment_id INTO p_payment_id;

    -- 5. Generar número de boleta
    v_receipt_number := fn_generar_codigo('BOL', 6);

    -- 6. Insertar recibo
    INSERT INTO payment_receipts (
        payment_id, receipt_number, issued_at, total_amount
    ) VALUES (
        p_payment_id, v_receipt_number, SYSTIMESTAMP, p_amount
    );

    COMMIT;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END prc_registrar_pago;
/
CREATE OR REPLACE PROCEDURE prc_generar_reporte_citas (
    p_fecha_inicio        IN DATE,
    p_fecha_fin           IN DATE,
    p_requested_by        IN NUMBER,
    p_report_format       IN VARCHAR2 DEFAULT 'TEXT',
    p_report_request_id   OUT NUMBER,
    p_generated_report_id OUT NUMBER
)
IS
    v_total         NUMBER := 0;
    v_completadas   NUMBER := 0;
    v_canceladas    NUMBER := 0;
    v_pendientes    NUMBER := 0;
    v_codigo        VARCHAR2(30);
    v_ruta          VARCHAR2(255);

    CURSOR c_citas IS
        SELECT a.appointment_status
        FROM appointments a
        INNER JOIN schedule_slots ss ON a.schedule_slot_id = ss.schedule_slot_id
        WHERE ss.slot_date BETWEEN p_fecha_inicio AND p_fecha_fin;

    v_estado VARCHAR2(30);
BEGIN
    -- 1. Validar rango
    IF p_fecha_inicio > p_fecha_fin THEN
        RAISE_APPLICATION_ERROR(-20040, 'Fecha inicio mayor que fecha fin');
    END IF;

    -- 2. Registrar solicitud
    INSERT INTO report_requests (
        report_type, requested_by_user_id,
        start_date, end_date, request_status, created_at
    ) VALUES (
        'APPOINTMENTS', p_requested_by,
        p_fecha_inicio, p_fecha_fin, 'PROCESSING', SYSTIMESTAMP
    ) RETURNING report_request_id INTO p_report_request_id;

    -- 3. Recorrer citas con cursor
    OPEN c_citas;
    LOOP
        FETCH c_citas INTO v_estado;
        EXIT WHEN c_citas%NOTFOUND;

        v_total := v_total + 1;

        IF v_estado = 'COMPLETED' THEN
            v_completadas := v_completadas + 1;
        ELSIF v_estado = 'CANCELLED' THEN
            v_canceladas := v_canceladas + 1;
        ELSIF v_estado = 'PENDING' THEN
            v_pendientes := v_pendientes + 1;
        END IF;
    END LOOP;
    CLOSE c_citas;

    -- 4. Generar código y ruta
    v_codigo := fn_generar_codigo('REP', 6);
    v_ruta   := '/demo/reportes/' || v_codigo || '.' || LOWER(p_report_format);

    -- 5. Insertar reporte generado
    INSERT INTO generated_reports (
        report_request_id, generated_by_user_id,
        report_type, generated_at, report_format,
        file_path, report_status
    ) VALUES (
        p_report_request_id, p_requested_by,
        'APPOINTMENTS', SYSTIMESTAMP, p_report_format,
        v_ruta, 'GENERATED'
    ) RETURNING generated_report_id INTO p_generated_report_id;

    -- 6. Actualizar solicitud
    UPDATE report_requests
    SET request_status = 'COMPLETED'
    WHERE report_request_id = p_report_request_id;

    COMMIT;

    -- 7. Mostrar resumen
    DBMS_OUTPUT.PUT_LINE('=== REPORTE GENERADO ===');
    DBMS_OUTPUT.PUT_LINE('Código: ' || v_codigo);
    DBMS_OUTPUT.PUT_LINE('Período: ' || fn_formatear_fecha(p_fecha_inicio) || 
                         ' al ' || fn_formatear_fecha(p_fecha_fin));
    DBMS_OUTPUT.PUT_LINE('Total citas: ' || v_total);
    DBMS_OUTPUT.PUT_LINE('  Completadas: ' || v_completadas);
    DBMS_OUTPUT.PUT_LINE('  Canceladas:  ' || v_canceladas);
    DBMS_OUTPUT.PUT_LINE('  Pendientes:  ' || v_pendientes);
    DBMS_OUTPUT.PUT_LINE('Ruta: ' || v_ruta);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END prc_generar_reporte_citas;
/