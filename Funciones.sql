CREATE SEQUENCE seq_codigos_generales
    START WITH 1000
    INCREMENT BY 1
    NOCACHE
    NOCYCLE;

CREATE OR REPLACE FUNCTION fn_limpiar_run (
    p_run IN VARCHAR2
) RETURN VARCHAR2
IS
    v_run_limpio VARCHAR2(20);
BEGIN
    -- Eliminar puntos y guiones del RUN
    v_run_limpio := REPLACE(REPLACE(p_run, '.', ''), '-', '');
    
    RETURN v_run_limpio;
END fn_limpiar_run;
/


CREATE OR REPLACE FUNCTION fn_calcular_dv_run (
    p_run_limpio VARCHAR2
) RETURN VARCHAR2
IS
    v_suma     NUMBER := 0;
    v_multi    NUMBER := 2;
    v_resto    NUMBER;
    v_dv       VARCHAR2(1);
    v_digito   NUMBER;
BEGIN
    IF p_run_limpio IS NULL THEN
        RETURN NULL;
    END IF;

    -- Recorrer el RUN de derecha a izquierda
    FOR i IN REVERSE 1..LENGTH(p_run_limpio) LOOP
        v_digito := TO_NUMBER(SUBSTR(p_run_limpio, i, 1));
        v_suma := v_suma + (v_digito * v_multi);

        v_multi := v_multi + 1;
        IF v_multi > 7 THEN
            v_multi := 2;
        END IF;
    END LOOP;

    v_resto := MOD(v_suma, 11);
    v_resto := 11 - v_resto;

    IF v_resto = 11 THEN
        v_dv := '0';
    ELSIF v_resto = 10 THEN
        v_dv := 'k';
    ELSE
        v_dv := TO_CHAR(v_resto);
    END IF;

    RETURN v_dv;
END fn_calcular_dv_run;
/

CREATE OR REPLACE FUNCTION fn_validar_run (
    p_run VARCHAR2
) RETURN NUMBER
IS
    v_run_limpio VARCHAR2(20);
    v_cuerpo     VARCHAR2(20);
    v_dv_recibido VARCHAR2(1);
    v_dv_esperado VARCHAR2(1);
BEGIN
    IF p_run IS NULL THEN
        RETURN 0;
    END IF;

    v_run_limpio := fn_limpiar_run(p_run);

    -- Debe tener al menos 2 caracteres (cuerpo + DV)
    IF LENGTH(v_run_limpio) < 2 THEN
        RETURN 0;
    END IF;

    -- Separar cuerpo y DV (último carácter)
    v_cuerpo      := SUBSTR(v_run_limpio, 1, LENGTH(v_run_limpio) - 1);
    v_dv_recibido := LOWER(SUBSTR(v_run_limpio, -1, 1));
    v_dv_esperado := fn_calcular_dv_run(v_cuerpo);

    IF v_dv_recibido = v_dv_esperado THEN
        RETURN 1;
    ELSE
        RETURN 0;
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN 0;
END fn_validar_run;
/



CREATE OR REPLACE FUNCTION fn_formatear_fecha (
    p_fecha   DATE,
    p_formato VARCHAR2 DEFAULT 'DD/MM/YYYY'
) RETURN VARCHAR2
IS
BEGIN
    IF p_fecha IS NULL THEN
        RETURN NULL;
    END IF;

    IF p_formato IS NULL THEN
        RETURN TO_CHAR(p_fecha, 'DD/MM/YYYY');
    END IF;

    RETURN TO_CHAR(p_fecha, p_formato);
END fn_formatear_fecha;
/



CREATE OR REPLACE FUNCTION fn_generar_codigo (
    p_prefijo  VARCHAR2,
    p_longitud NUMBER DEFAULT 6
) RETURN VARCHAR2
IS
    v_numero  NUMBER;
    v_relleno NUMBER;
    v_codigo  VARCHAR2(30);
BEGIN
    IF p_prefijo IS NULL THEN
        RETURN NULL;
    END IF;

    IF p_longitud IS NULL OR p_longitud <= 0 THEN
        v_relleno := 6;
    ELSE
        v_relleno := p_longitud;
    END IF;

    v_numero := seq_codigos_generales.NEXTVAL;
    v_codigo := p_prefijo || '-' || LPAD(TO_CHAR(v_numero), v_relleno, '0');

    RETURN v_codigo;
END fn_generar_codigo;
/

CREATE OR REPLACE FUNCTION fn_contar_pacientes_activos
RETURN NUMBER
IS
    v_total NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO v_total
    FROM users u
    INNER JOIN patient_profiles pp ON pp.user_id = u.user_id
    WHERE u.active = 1;

    RETURN v_total;
END fn_contar_pacientes_activos;
/
