

SET SERVEROUTPUT ON;

-- ============================================================
-- BLOQUE 1: RECORD
-- Objetivo: agrupar los datos principales de una reserva.
-- ============================================================
DECLARE
    TYPE t_reserva_rec IS RECORD (
        appointment_id     appointments.appointment_id%TYPE,
        patient_user_id    appointments.patient_user_id%TYPE,
        doctor_id          appointments.doctor_id%TYPE,
        specialty_id       appointments.specialty_id%TYPE,
        schedule_slot_id   appointments.schedule_slot_id%TYPE,
        appointment_status appointments.appointment_status%TYPE,
        reason             appointments.reason%TYPE
    );

    v_reserva t_reserva_rec;
BEGIN
    SELECT appointment_id,
           patient_user_id,
           doctor_id,
           specialty_id,
           schedule_slot_id,
           appointment_status,
           reason
    INTO   v_reserva
    FROM   appointments
    WHERE  appointment_id = 6;

    DBMS_OUTPUT.PUT_LINE('=== RECORD: datos de una reserva ===');
    DBMS_OUTPUT.PUT_LINE('ID de reserva: ' || v_reserva.appointment_id);
    DBMS_OUTPUT.PUT_LINE('ID de paciente: ' || v_reserva.patient_user_id);
    DBMS_OUTPUT.PUT_LINE('ID de medico: ' || v_reserva.doctor_id);
    DBMS_OUTPUT.PUT_LINE('ID de especialidad: ' || v_reserva.specialty_id);
    DBMS_OUTPUT.PUT_LINE('ID de bloque horario: ' || v_reserva.schedule_slot_id);
    DBMS_OUTPUT.PUT_LINE('Estado: ' || v_reserva.appointment_status);
    DBMS_OUTPUT.PUT_LINE('Motivo: ' || v_reserva.reason);
END;
/

-- ============================================================
-- BLOQUE 2: VARRAY
-- Objetivo: almacenar y mostrar, en orden, los IDs de las cinco
-- especialidades cargadas en los datos de practica.
-- ============================================================
DECLARE
    TYPE t_especialidad_id_array IS VARRAY(10) OF NUMBER;

    v_especialidades t_especialidad_id_array :=
        t_especialidad_id_array(1, 2, 3, 4, 5);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=== VARRAY: especialidades a procesar ===');
    DBMS_OUTPUT.PUT_LINE('Cantidad de IDs: ' || v_especialidades.COUNT);

    FOR i IN 1 .. v_especialidades.COUNT LOOP
        DBMS_OUTPUT.PUT_LINE(
            'Especialidad en posicion ' || i ||
            ': ID ' || v_especialidades(i)
        );
    END LOOP;
END;
/

-- Fin del anexo.
