-- Paquetes PL/SQL adicionales para MediReservas.
-- Ejecutar después de crear las tablas y cargar Funciones.sql.
-- En SQL Developer, ejecutar como script (F5).

-- ============================================================
-- PAQUETE 1: consultas de disponibilidad de agenda
-- Justificación: permite consultar y resumir los bloques libres
-- sin crear reservas ni duplicar prc_agendar_cita.
-- ============================================================
CREATE OR REPLACE PACKAGE pkg_agenda AS
    PROCEDURE prc_listar_slots_disponibles (
        p_doctor_id IN schedule_slots.doctor_id%TYPE,
        p_fecha     IN schedule_slots.slot_date%TYPE
    );

    FUNCTION fn_contar_slots_disponibles (
        p_doctor_id IN schedule_slots.doctor_id%TYPE,
        p_fecha     IN schedule_slots.slot_date%TYPE
    ) RETURN NUMBER;
END pkg_agenda;
/

CREATE OR REPLACE PACKAGE BODY pkg_agenda AS
    -- Elemento privado: solo puede ser utilizado dentro de este paquete.
    PROCEDURE prc_validar_consulta (
        p_doctor_id IN schedule_slots.doctor_id%TYPE,
        p_fecha     IN schedule_slots.slot_date%TYPE
    ) IS
    BEGIN
        IF p_doctor_id IS NULL OR p_fecha IS NULL THEN
            RAISE_APPLICATION_ERROR(-20050, 'Doctor y fecha son obligatorios');
        END IF;
    END prc_validar_consulta;

    PROCEDURE prc_listar_slots_disponibles (
        p_doctor_id IN schedule_slots.doctor_id%TYPE,
        p_fecha     IN schedule_slots.slot_date%TYPE
    ) IS
        v_encontrados NUMBER := 0;
    BEGIN
        prc_validar_consulta(p_doctor_id, p_fecha);

        DBMS_OUTPUT.PUT_LINE('Bloques disponibles para el doctor ' || p_doctor_id);
        DBMS_OUTPUT.PUT_LINE('Fecha: ' || TO_CHAR(p_fecha, 'DD/MM/YYYY'));

        FOR r_slot IN (
            SELECT ss.schedule_slot_id, ss.start_time, ss.end_time
            FROM schedule_slots ss
            INNER JOIN doctors d ON d.doctor_id = ss.doctor_id
            WHERE ss.doctor_id = p_doctor_id
              AND d.active = 1
              AND ss.slot_date >= GREATEST(TRUNC(p_fecha), TRUNC(SYSDATE))
              AND ss.slot_date < TRUNC(p_fecha) + 1
              AND (ss.slot_date > TRUNC(SYSDATE)
                   OR ss.start_time >= TO_CHAR(SYSDATE, 'HH24:MI:SS'))
              AND ss.slot_status = 'AVAILABLE'
            ORDER BY ss.start_time
        ) LOOP
            v_encontrados := v_encontrados + 1;
            DBMS_OUTPUT.PUT_LINE(
                'ID: ' || r_slot.schedule_slot_id ||
                ' | ' || r_slot.start_time || ' - ' || r_slot.end_time
            );
        END LOOP;

        IF v_encontrados = 0 THEN
            DBMS_OUTPUT.PUT_LINE('No hay bloques disponibles para esa fecha.');
        END IF;
    END prc_listar_slots_disponibles;

    FUNCTION fn_contar_slots_disponibles (
        p_doctor_id IN schedule_slots.doctor_id%TYPE,
        p_fecha     IN schedule_slots.slot_date%TYPE
    ) RETURN NUMBER IS
        v_total NUMBER;
    BEGIN
        prc_validar_consulta(p_doctor_id, p_fecha);

        SELECT COUNT(*)
        INTO v_total
        FROM schedule_slots ss
        INNER JOIN doctors d ON d.doctor_id = ss.doctor_id
        WHERE ss.doctor_id = p_doctor_id
          AND d.active = 1
          AND ss.slot_date >= GREATEST(TRUNC(p_fecha), TRUNC(SYSDATE))
          AND ss.slot_date < TRUNC(p_fecha) + 1
          AND (ss.slot_date > TRUNC(SYSDATE)
               OR ss.start_time >= TO_CHAR(SYSDATE, 'HH24:MI:SS'))
          AND ss.slot_status = 'AVAILABLE';

        RETURN v_total;
    END fn_contar_slots_disponibles;
END pkg_agenda;
/

-- ============================================================
-- PAQUETE 2: consultas de ficha de paciente
-- Justificación: centraliza una lectura reutilizable de datos
-- demográficos y clínicos básicos, sin duplicar el registro de
-- pacientes de prc_registrar_paciente.
-- ============================================================
CREATE OR REPLACE PACKAGE pkg_pacientes AS
    PROCEDURE prc_obtener_resumen (
        p_user_id          IN  users.user_id%TYPE,
        p_nombre_completo  OUT VARCHAR2,
        p_run              OUT users.run%TYPE,
        p_prevision        OUT patient_profiles.health_insurance%TYPE
    );

    FUNCTION fn_calcular_edad (
        p_user_id IN users.user_id%TYPE
    ) RETURN NUMBER;
END pkg_pacientes;
/

CREATE OR REPLACE PACKAGE BODY pkg_pacientes AS
    -- Elemento privado: encapsula la lectura de la fecha de nacimiento.
    FUNCTION fn_obtener_fecha_nacimiento (
        p_user_id IN users.user_id%TYPE
    ) RETURN user_profiles.birth_date%TYPE IS
        v_fecha user_profiles.birth_date%TYPE;
    BEGIN
        SELECT up.birth_date
        INTO v_fecha
        FROM users u
        INNER JOIN user_profiles up ON up.user_id = u.user_id
        INNER JOIN patient_profiles pp ON pp.user_id = u.user_id
        WHERE u.user_id = p_user_id;

        RETURN v_fecha;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20053, 'No se encontró la ficha del paciente');
    END fn_obtener_fecha_nacimiento;

    PROCEDURE prc_obtener_resumen (
        p_user_id          IN  users.user_id%TYPE,
        p_nombre_completo  OUT VARCHAR2,
        p_run              OUT users.run%TYPE,
        p_prevision        OUT patient_profiles.health_insurance%TYPE
    ) IS
    BEGIN
        SELECT up.first_name || ' ' || up.last_name,
               u.run,
               pp.health_insurance
        INTO p_nombre_completo, p_run, p_prevision
        FROM users u
        INNER JOIN user_profiles up ON up.user_id = u.user_id
        INNER JOIN patient_profiles pp ON pp.user_id = u.user_id
        WHERE u.user_id = p_user_id;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RAISE_APPLICATION_ERROR(-20052, 'No se encontró la ficha del paciente');
    END prc_obtener_resumen;

    FUNCTION fn_calcular_edad (
        p_user_id IN users.user_id%TYPE
    ) RETURN NUMBER IS
        v_fecha_nacimiento user_profiles.birth_date%TYPE;
    BEGIN
        v_fecha_nacimiento := fn_obtener_fecha_nacimiento(p_user_id);

        IF v_fecha_nacimiento IS NULL THEN
            RETURN NULL;
        END IF;

        RETURN TRUNC(MONTHS_BETWEEN(TRUNC(SYSDATE), v_fecha_nacimiento) / 12);
    END fn_calcular_edad;
END pkg_pacientes;
/
