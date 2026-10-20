-- Excepcion predefinida
SET SERVEROUTPUT ON;

DECLARE
    v_appointment_id appointments.appointment_id%TYPE := 9999;
    v_patient_id     appointments.patient_user_id%TYPE;
    v_doctor_id      appointments.doctor_id%TYPE;
    v_status         appointments.appointment_status%TYPE;
BEGIN
    SELECT patient_user_id,
           doctor_id,
           appointment_status
    INTO   v_patient_id,
           v_doctor_id,
           v_status
    FROM appointments
    WHERE appointment_id = v_appointment_id;

    DBMS_OUTPUT.PUT_LINE('Cita encontrada.');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE(
            'No existe una cita con el ID ' || v_appointment_id
        );
END;
/

--Excepcion personalizada
SET SERVEROUTPUT ON;

DECLARE
    v_amount NUMBER := -15000;

    e_invalid_amount EXCEPTION;
BEGIN

    IF v_amount <= 0 THEN
        RAISE e_invalid_amount;
    END IF;

    DBMS_OUTPUT.PUT_LINE('Monto válido para realizar el pago.');

EXCEPTION
    WHEN e_invalid_amount THEN
        DBMS_OUTPUT.PUT_LINE(
            'Error: el monto del pago debe ser mayor a cero.'
        );
END;
/
