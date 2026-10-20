CREATE OR REPLACE PROCEDURE prc_listar_pacientes_activos IS
    -- Cursor simple sin parámetros
    CURSOR c_pacientes IS
        SELECT 
            u.user_id,
            u.run,
            up.first_name,
            up.last_name,
            up.phone,
            p.health_insurance
        FROM users u
        INNER JOIN user_profiles up ON u.user_id = up.user_id
        INNER JOIN patient_profiles p ON u.user_id = p.user_id
        WHERE u.active = 1
        ORDER BY up.last_name, up.first_name;
    
    v_paciente c_pacientes%ROWTYPE;
    v_contador NUMBER := 0;
    
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== LISTADO DE PACIENTES ACTIVOS ===');
    DBMS_OUTPUT.PUT_LINE('');
    
    OPEN c_pacientes;
    LOOP
        FETCH c_pacientes INTO v_paciente;
        EXIT WHEN c_pacientes%NOTFOUND;
        
        v_contador := v_contador + 1;
        
        DBMS_OUTPUT.PUT_LINE('Paciente #' || v_contador);
        DBMS_OUTPUT.PUT_LINE('  Nombre: ' || v_paciente.first_name || ' ' || v_paciente.last_name);
        DBMS_OUTPUT.PUT_LINE('  RUN: ' || v_paciente.run);
        DBMS_OUTPUT.PUT_LINE('  Teléfono: ' || v_paciente.phone);
        DBMS_OUTPUT.PUT_LINE('  Isapre/Fonasa: ' || v_paciente.health_insurance);
        DBMS_OUTPUT.PUT_LINE('-----------------------------------');
    END LOOP;
    CLOSE c_pacientes;
    
    DBMS_OUTPUT.PUT_LINE('Total pacientes: ' || v_contador);
END;
/

CREATE OR REPLACE PROCEDURE prc_mostrar_citas_doctor(
    p_doctor_id NUMBER,
    p_fecha_desde DATE,
    p_fecha_hasta DATE
) IS
    -- Cursor con parámetros
    CURSOR c_citas_doctor (
        p_doctor_id NUMBER,
        p_fecha_desde DATE,
        p_fecha_hasta DATE
    ) IS
        SELECT 
            a.appointment_id,
            a.patient_user_id,
            CONCAT(up.first_name, ' ', up.last_name) AS paciente,
            ss.slot_date,
            ss.start_time,
            a.appointment_status,
            a.reason,
            p.amount AS monto_pago
        FROM appointments a
        INNER JOIN schedule_slots ss ON a.schedule_slot_id = ss.schedule_slot_id
        INNER JOIN user_profiles up ON a.patient_user_id = up.user_id
        LEFT JOIN payments p ON a.appointment_id = p.appointment_id
        WHERE a.doctor_id = p_doctor_id
          AND ss.slot_date BETWEEN p_fecha_desde AND p_fecha_hasta
        ORDER BY ss.slot_date, ss.start_time;
    
    v_cita c_citas_doctor%ROWTYPE;
    v_contador NUMBER := 0;
    v_total_pagos NUMBER := 0;
    
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== CITAS DEL DOCTOR ===');
    DBMS_OUTPUT.PUT_LINE('ID Doctor: ' || p_doctor_id);
    DBMS_OUTPUT.PUT_LINE('Período: ' || TO_CHAR(p_fecha_desde, 'DD/MM/YYYY') || 
                         ' al ' || TO_CHAR(p_fecha_hasta, 'DD/MM/YYYY'));
    DBMS_OUTPUT.PUT_LINE('========================');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- Abrir cursor con parámetros
    OPEN c_citas_doctor(p_doctor_id, p_fecha_desde, p_fecha_hasta);
    
    LOOP
        FETCH c_citas_doctor INTO v_cita;
        EXIT WHEN c_citas_doctor%NOTFOUND;
        
        v_contador := v_contador + 1;
        
        IF v_cita.monto_pago IS NOT NULL THEN
            v_total_pagos := v_total_pagos + v_cita.monto_pago;
        END IF;
        
        DBMS_OUTPUT.PUT_LINE('Cita #' || v_contador);
        DBMS_OUTPUT.PUT_LINE('  Fecha: ' || TO_CHAR(v_cita.slot_date, 'DD/MM/YYYY'));
        DBMS_OUTPUT.PUT_LINE('  Hora: ' || v_cita.start_time);
        DBMS_OUTPUT.PUT_LINE('  Paciente: ' || v_cita.paciente);
        DBMS_OUTPUT.PUT_LINE('  Estado: ' || v_cita.appointment_status);
        DBMS_OUTPUT.PUT_LINE('  Motivo: ' || v_cita.reason);
        DBMS_OUTPUT.PUT_LINE('  Monto: ' || NVL(TO_CHAR(v_cita.monto_pago, 'FM$999,999,999'), 'Pendiente'));
        DBMS_OUTPUT.PUT_LINE('-----------------------------------');
    END LOOP;
    
    CLOSE c_citas_doctor;
    
    DBMS_OUTPUT.PUT_LINE('Total citas: ' || v_contador);
    DBMS_OUTPUT.PUT_LINE('Total ingresos: ' || TO_CHAR(v_total_pagos, 'FM$999,999,999'));
END;
/

CREATE OR REPLACE PROCEDURE prc_reporte_ocupacion_doctores_anidado(
    p_fecha_inicio DATE,
    p_fecha_fin DATE
) IS
    -- CURSOR EXTERIOR: Doctores con su especialidad principal
    CURSOR c_doctores IS
        SELECT 
            d.doctor_id,
            CONCAT(up.first_name, ' ', up.last_name) AS nombre,
            s.specialty_name AS especialidad
        FROM doctors d
        INNER JOIN user_profiles up ON d.user_id = up.user_id
        INNER JOIN doctor_specialties ds ON d.doctor_id = ds.doctor_id
        INNER JOIN specialties s ON ds.specialty_id = s.specialty_id
        WHERE d.active = 1
          AND ds.is_primary = 1
        ORDER BY s.specialty_name, up.last_name;
    
    -- CURSOR INTERIOR CON PARÁMETROS: Estadísticas del doctor
    CURSOR c_estadisticas_doctor (
        p_doctor_id NUMBER,
        p_fecha_inicio DATE,
        p_fecha_fin DATE
    ) IS
        SELECT 
            TO_CHAR(ss.slot_date, 'Day') AS dia_semana,
            COUNT(*) AS total,
            SUM(CASE WHEN a.appointment_status = 'COMPLETED' THEN 1 ELSE 0 END) AS completadas,
            SUM(CASE WHEN a.appointment_status = 'CANCELLED' THEN 1 ELSE 0 END) AS canceladas
        FROM appointments a
        INNER JOIN schedule_slots ss ON a.schedule_slot_id = ss.schedule_slot_id
        WHERE a.doctor_id = p_doctor_id
          AND ss.slot_date BETWEEN p_fecha_inicio AND p_fecha_fin
        GROUP BY TO_CHAR(ss.slot_date, 'Day')
        ORDER BY MIN(ss.slot_date);
    
    -- Variables para los bucles
    v_doctor c_doctores%ROWTYPE;
    v_estadistica c_estadisticas_doctor%ROWTYPE;
    v_total_general NUMBER := 0;
    
BEGIN
    DBMS_OUTPUT.PUT_LINE('============================================');
    DBMS_OUTPUT.PUT_LINE('REPORTE DE OCUPACIÓN DE DOCTORES');
    DBMS_OUTPUT.PUT_LINE('Período: ' || TO_CHAR(p_fecha_inicio, 'DD/MM/YYYY') || 
                         ' al ' || TO_CHAR(p_fecha_fin, 'DD/MM/YYYY'));
    DBMS_OUTPUT.PUT_LINE('============================================');
    DBMS_OUTPUT.PUT_LINE('');
    
    -- LOOP EXTERIOR: Recorrer doctores
    OPEN c_doctores;
    LOOP
        FETCH c_doctores INTO v_doctor;
        EXIT WHEN c_doctores%NOTFOUND;
        
        DBMS_OUTPUT.PUT_LINE('=== ' || v_doctor.nombre || ' ===');
        DBMS_OUTPUT.PUT_LINE('Especialidad: ' || v_doctor.especialidad);
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('Día        | Total | OK | CAN');
        DBMS_OUTPUT.PUT_LINE('-----------|-------|----|-----');
        
        -- LOOP INTERIOR: Estadísticas por día
        OPEN c_estadisticas_doctor(v_doctor.doctor_id, p_fecha_inicio, p_fecha_fin);
        LOOP
            FETCH c_estadisticas_doctor INTO v_estadistica;
            EXIT WHEN c_estadisticas_doctor%NOTFOUND;
            
            DBMS_OUTPUT.PUT_LINE(
                RPAD(TRIM(v_estadistica.dia_semana), 11) || ' | ' ||
                LPAD(v_estadistica.total, 5) || ' | ' ||
                LPAD(v_estadistica.completadas, 2) || ' | ' ||
                LPAD(v_estadistica.canceladas, 3)
            );
            
            v_total_general := v_total_general + v_estadistica.total;
        END LOOP;
        CLOSE c_estadisticas_doctor;
        
        DBMS_OUTPUT.PUT_LINE('-----------------------------------');
        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;
    CLOSE c_doctores;
    
    DBMS_OUTPUT.PUT_LINE('============================================');
    DBMS_OUTPUT.PUT_LINE('TOTAL GENERAL DE CITAS: ' || v_total_general);
    DBMS_OUTPUT.PUT_LINE('============================================');
END;
/

