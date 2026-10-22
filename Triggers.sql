CREATE OR REPLACE TRIGGER trg_auditar_sentencia_cita
AFTER INSERT OR UPDATE OR DELETE ON appointments
BEGIN
    INSERT INTO appointment_statement_audit (
        table_name, operation_name, event_at, db_user
    ) VALUES (
        'APPOINTMENTS', ORA_SYSEVENT, SYSTIMESTAMP,
        SYS_CONTEXT('USERENV', 'SESSION_USER')
    );
END trg_auditar_sentencia_cita;
/

CREATE OR REPLACE TRIGGER trg_validar_cita_antes_insert
BEFORE INSERT ON appointments
FOR EACH ROW
DECLARE
    v_existe      NUMBER;
    v_slot_estado VARCHAR2(30);
    v_slot_fecha  DATE;
    v_atiende     NUMBER;
BEGIN
    -- 1. Verificar paciente activo
    SELECT COUNT(*) INTO v_existe
    FROM users u
    INNER JOIN patient_profiles pp ON u.user_id = pp.user_id
    WHERE u.user_id = :NEW.patient_user_id AND u.active = 1;

    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20101, 'Paciente no existe o está inactivo');
    END IF;

    -- 2. Verificar doctor activo
    SELECT COUNT(*) INTO v_existe
    FROM doctors
    WHERE doctor_id = :NEW.doctor_id AND active = 1;

    IF v_existe = 0 THEN
        RAISE_APPLICATION_ERROR(-20102, 'Doctor no existe o está inactivo');
    END IF;

    -- 3. Verificar slot disponible
    SELECT slot_status, slot_date
    INTO v_slot_estado, v_slot_fecha
    FROM schedule_slots
    WHERE schedule_slot_id = :NEW.schedule_slot_id;

    IF v_slot_estado <> 'AVAILABLE' THEN
        RAISE_APPLICATION_ERROR(-20103, 'Slot no disponible: ' || v_slot_estado);
    END IF;

    IF v_slot_fecha < TRUNC(SYSDATE) THEN
        RAISE_APPLICATION_ERROR(-20104, 'Slot en fecha pasada');
    END IF;

    -- 4. Verificar especialidad del doctor
    SELECT COUNT(*) INTO v_atiende
    FROM doctor_specialties
    WHERE doctor_id = :NEW.doctor_id AND specialty_id = :NEW.specialty_id;

    IF v_atiende = 0 THEN
        RAISE_APPLICATION_ERROR(-20105, 'Doctor no atiende la especialidad');
    END IF;

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20106, 'Slot no encontrado: ' || :NEW.schedule_slot_id);
END trg_validar_cita_antes_insert;
/

CREATE OR REPLACE TRIGGER trg_historial_estado_cita
BEFORE UPDATE OF appointment_status ON appointments
FOR EACH ROW
WHEN (OLD.appointment_status <> NEW.appointment_status)
BEGIN
    INSERT INTO appointment_status_history (
        appointment_id, old_status, new_status,
        changed_by_user_id, change_reason, changed_at
    ) VALUES (
        :OLD.appointment_id,
        :OLD.appointment_status,
        :NEW.appointment_status,
        NULL,
        'Cambio automático por trigger',
        SYSTIMESTAMP
    );
END trg_historial_estado_cita;
/

CREATE OR REPLACE TRIGGER trg_sincronizar_slot_cita
AFTER INSERT ON appointments
FOR EACH ROW
BEGIN
    UPDATE schedule_slots
    SET slot_status   = 'BOOKED',
        appointment_id = :NEW.appointment_id
    WHERE schedule_slot_id = :NEW.schedule_slot_id;
END trg_sincronizar_slot_cita;
/

CREATE OR REPLACE TRIGGER trg_generar_recibo_automatico
AFTER INSERT ON payments
FOR EACH ROW
WHEN (NEW.payment_status = 'PAID')
DECLARE
    v_receipt_number VARCHAR2(30);
    v_existe         NUMBER;
BEGIN
    -- Verificar que no exista recibo para este pago
    SELECT COUNT(*) INTO v_existe
    FROM payment_receipts
    WHERE payment_id = :NEW.payment_id;

    IF v_existe = 0 THEN
        v_receipt_number := fn_generar_codigo('BOL', 6);

        INSERT INTO payment_receipts (
            payment_id, receipt_number, issued_at, total_amount
        ) VALUES (
            :NEW.payment_id, v_receipt_number, SYSTIMESTAMP, :NEW.amount
        );
    END IF;
END trg_generar_recibo_automatico;
/

CREATE OR REPLACE TRIGGER trg_auditar_cambio_pago
AFTER UPDATE OF payment_status ON payments
FOR EACH ROW
WHEN (OLD.payment_status <> NEW.payment_status AND NEW.payment_status = 'REFUNDED')
DECLARE
    v_existe NUMBER;
BEGIN
    -- Evitar duplicados
    SELECT COUNT(*) INTO v_existe
    FROM refunds
    WHERE payment_id = :NEW.payment_id
      AND refund_status IN ('PENDING', 'COMPLETED');

    IF v_existe = 0 THEN
        INSERT INTO refunds (
            payment_id, refund_amount, refund_reason,
            refund_status, created_at
        ) VALUES (
            :NEW.payment_id, :NEW.amount,
            'Reembolso automático por cambio de estado',
            'PENDING', SYSTIMESTAMP
        );
    END IF;
END trg_auditar_cambio_pago;
/
