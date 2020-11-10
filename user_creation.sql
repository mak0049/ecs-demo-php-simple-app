SET SERVEROUTPUT ON
SET LINESIZE 200

DECLARE
    TYPE T_CURSOR IS    REF CURSOR;
    V_CURSOR            T_CURSOR;
    V_USER                VARCHAR2 (30) := UPPER ('&1');
    V_NEW_USER            VARCHAR2 (30) := UPPER ('&2');
    V_PASSWORD1            VARCHAR2 (30);
    V_PASSWORD2            VARCHAR2 (30);
    V_D_TBS                VARCHAR2 (30);
    V_T_TBS                VARCHAR2 (30);
    V_PROFILE            VARCHAR2 (30);
    V_LOCK_DATE            DATE;
    V_COUNTER            NUMBER;
    V_MAX_BYTES            NUMBER;
    V_PRIVILEGE            VARCHAR2 (40);
    V_ADMIN_OPT            VARCHAR2 (3);
    V_ROLE                VARCHAR2 (30);
    V_DEF_ROLE            VARCHAR2 (3);
    V_DEFROLE            NUMBER;
    V_OUTPUT            VARCHAR2 (500);
    V_TABLE_NAME        VARCHAR2 (30);
    V_OWNER                VARCHAR2 (30);
    V_GRANT_OPT            VARCHAR2 (3);
    V_HIER_OPT            VARCHAR2 (3);
    V_COL_NAME            VARCHAR2 (30);
    V_AUDIT_OPT            VARCHAR2 (40);
    V_SUCCESS            VARCHAR2 (10);
    V_FAILURE            VARCHAR2 (10);

BEGIN
    SELECT COUNT (*)
      INTO V_COUNTER
      FROM DBA_USERS
     WHERE USERNAME = V_USER;

    IF V_COUNTER <> 0
    THEN
        IF V_NEW_USER IS NULL
        THEN
            V_NEW_USER := V_USER;
        END IF;

        SELECT B.PASSWORD, A.PASSWORD, A.DEFAULT_TABLESPACE, A.TEMPORARY_TABLESPACE, A.PROFILE, A.LOCK_DATE
          INTO V_PASSWORD1, V_PASSWORD2, V_D_TBS, V_T_TBS, V_PROFILE, V_LOCK_DATE
          FROM DBA_USERS A, SYS.USER$ B
         WHERE A.USERNAME = V_USER
         AND A.USERNAME = B.NAME;

        --Create User Command * Begin
        DBMS_OUTPUT.PUT_LINE ('--Create User command');
        DBMS_OUTPUT.PUT_LINE ('CREATE USER ' || V_NEW_USER);
        IF V_PASSWORD2 = 'EXTERNAL'
        THEN
            DBMS_OUTPUT.PUT_LINE ('IDENTIFIED EXTERNALLY');
        ELSE
            DBMS_OUTPUT.PUT_LINE ('IDENTIFIED BY VALUES ''' || V_PASSWORD1 || '''');
        END IF;
        DBMS_OUTPUT.PUT_LINE ('DEFAULT TABLESPACE ' || V_D_TBS);
        DBMS_OUTPUT.PUT_LINE ('TEMPORARY TABLESPACE ' || V_T_TBS);
        DBMS_OUTPUT.PUT_LINE ('PROFILE ' || V_PROFILE);
        IF V_LOCK_DATE IS NULL THEN
            DBMS_OUTPUT.PUT_LINE ('ACCOUNT UNLOCK;');
        ELSE
            DBMS_OUTPUT.PUT_LINE ('ACCOUNT LOCK;');
        END IF;
        --Create User Command * End

        --Tablespace Quotas * Begin
        SELECT COUNT (*)
          INTO V_COUNTER
          FROM DBA_TS_QUOTAS
         WHERE USERNAME = V_USER;

        IF V_COUNTER > 0
        THEN
            DBMS_OUTPUT.PUT_LINE ('-- ' || V_COUNTER || ' tablespace quotas');

            OPEN V_CURSOR FOR
                SELECT TABLESPACE_NAME, MAX_BYTES
                  FROM DBA_TS_QUOTAS
                 WHERE USERNAME = V_USER;

            LOOP
                FETCH V_CURSOR
                INTO V_D_TBS, V_MAX_BYTES;

                EXIT WHEN V_CURSOR%NOTFOUND;

                IF V_MAX_BYTES = -1
                THEN
                    DBMS_OUTPUT.PUT_LINE ('ALTER USER ' || V_NEW_USER || ' QUOTA UNLIMITED ON ' || V_D_TBS || ';');
                ELSE
                    DBMS_OUTPUT.PUT_LINE ('ALTER USER ' || V_NEW_USER || ' QUOTA ' || V_MAX_BYTES || ' ON ' || V_D_TBS || ';');
                END IF;
            END LOOP;

            CLOSE V_CURSOR;
        END IF;
        --Tablespace Quotas * End

        --Roles * Begin
        SELECT COUNT (*)
          INTO V_COUNTER
          FROM DBA_ROLE_PRIVS
         WHERE GRANTEE = V_USER;

        IF V_COUNTER > 0
        THEN
            DBMS_OUTPUT.PUT_LINE ('-- ' || V_COUNTER || ' Roles');

            SELECT DEFROLE
              INTO V_DEFROLE
              FROM SYS.USER$
             WHERE NAME = V_USER;

            CASE V_DEFROLE
                WHEN 0
                THEN
                    DBMS_OUTPUT.PUT_LINE (
                        'ALTER USER ' || V_NEW_USER || ' DEFAULT ROLE NONE;');
                WHEN 1
                THEN
                    DBMS_OUTPUT.PUT_LINE (
                        'ALTER USER ' || V_NEW_USER || ' DEFAULT ROLE ALL;');
                ELSE
                    NULL;
            END CASE;

            OPEN V_CURSOR FOR
                SELECT GRANTED_ROLE, ADMIN_OPTION, DEFAULT_ROLE
                  FROM DBA_ROLE_PRIVS
                 WHERE GRANTEE = V_USER;

            LOOP
                FETCH V_CURSOR
                INTO V_ROLE, V_ADMIN_OPT, V_DEF_ROLE;

                EXIT WHEN V_CURSOR%NOTFOUND;
                V_OUTPUT := 'GRANT ' || V_ROLE || ' TO ' || V_NEW_USER;

                IF V_ADMIN_OPT = 'NO'
                THEN
                    V_OUTPUT := V_OUTPUT || ';';
                ELSE
                    V_OUTPUT := V_OUTPUT || ' WITH ADMIN OPTION;';
                END IF;

                DBMS_OUTPUT.PUT_LINE (V_OUTPUT);

                IF V_DEFROLE = 2 AND V_DEF_ROLE='YES'
                THEN
                    DBMS_OUTPUT.PUT_LINE ('ALTER USER ' || V_NEW_USER || ' DEFAULT ROLE ' || V_ROLE || ';');
                END IF;
            END LOOP;

            CLOSE V_CURSOR;
        END IF;
        --Roles * End

        --System Privileges * Begin
        SELECT COUNT (*)
          INTO V_COUNTER
          FROM DBA_SYS_PRIVS
         WHERE GRANTEE = V_USER;

        IF V_COUNTER > 0
        THEN
            DBMS_OUTPUT.PUT_LINE ('-- ' || V_COUNTER || ' system privileges');

            OPEN V_CURSOR FOR
                SELECT PRIVILEGE, ADMIN_OPTION
                  FROM DBA_SYS_PRIVS
                 WHERE GRANTEE = V_USER;

            LOOP
                FETCH V_CURSOR
                INTO V_PRIVILEGE, V_ADMIN_OPT;

                EXIT WHEN V_CURSOR%NOTFOUND;
                V_OUTPUT := 'GRANT ' || V_PRIVILEGE || ' TO ' || V_NEW_USER;

                IF V_ADMIN_OPT = 'NO'
                THEN
                    V_OUTPUT := V_OUTPUT || ';';
                ELSE
                    V_OUTPUT := V_OUTPUT || ' WITH ADMIN OPTION;';
                END IF;

                DBMS_OUTPUT.PUT_LINE (V_OUTPUT);
            END LOOP;

            CLOSE V_CURSOR;
        END IF;
        --System Privileges * End

        --Object Privileges * Begin
        SELECT COUNT (*)
          INTO V_COUNTER
          FROM DBA_TAB_PRIVS
         WHERE GRANTEE = V_USER;

        IF V_COUNTER > 0
        THEN
            DBMS_OUTPUT.PUT_LINE ('-- ' || V_COUNTER || ' object privileges');

            OPEN V_CURSOR FOR
                SELECT PRIVILEGE, OWNER, TABLE_NAME, GRANTABLE, HIERARCHY
                  FROM DBA_TAB_PRIVS
                 WHERE GRANTEE = V_USER;

            LOOP
                FETCH V_CURSOR
                INTO V_PRIVILEGE, V_OWNER, V_TABLE_NAME, V_GRANT_OPT, V_HIER_OPT;

                EXIT WHEN V_CURSOR%NOTFOUND;
                V_OUTPUT := 'GRANT ' || V_PRIVILEGE || ' ON ' || V_OWNER || '.' || V_TABLE_NAME || ' TO ' || V_NEW_USER;

                IF V_HIER_OPT = 'YES'
                THEN
                    V_OUTPUT := V_OUTPUT || ' WITH HIERARCHY OPTION';
                END IF;

                IF V_GRANT_OPT = 'NO'
                THEN
                    V_OUTPUT := V_OUTPUT || ';';
                ELSE
                    V_OUTPUT := V_OUTPUT || ' WITH GRANT OPTION;';
                END IF;

                DBMS_OUTPUT.PUT_LINE (V_OUTPUT);
            END LOOP;

            CLOSE V_CURSOR;
        END IF;
        --Object Privileges * End

        --Column Privileges * Begin
        SELECT COUNT (*)
          INTO V_COUNTER
          FROM DBA_COL_PRIVS
         WHERE GRANTEE = V_USER;

        IF V_COUNTER > 0
        THEN
            DBMS_OUTPUT.PUT_LINE ('-- ' || V_COUNTER || ' column privileges');

            OPEN V_CURSOR FOR
                SELECT PRIVILEGE, OWNER, TABLE_NAME, COLUMN_NAME, GRANTABLE
                  FROM DBA_COL_PRIVS
                 WHERE GRANTEE = V_USER;

            LOOP
                FETCH V_CURSOR
                INTO V_PRIVILEGE, V_OWNER, V_TABLE_NAME, V_COL_NAME, V_GRANT_OPT;

                EXIT WHEN V_CURSOR%NOTFOUND;

                V_OUTPUT := 'GRANT ' || V_PRIVILEGE || ' (' || V_COL_NAME || ') ON ' || V_OWNER || '.' || V_TABLE_NAME || ' TO ' || V_NEW_USER;

                IF V_GRANT_OPT = 'NO'
                THEN
                    V_OUTPUT := V_OUTPUT || ';';
                ELSE
                    V_OUTPUT := V_OUTPUT || ' WITH GRANT OPTION;';
                END IF;

                DBMS_OUTPUT.PUT_LINE (V_OUTPUT);
            END LOOP;
            
            CLOSE V_CURSOR;
        END IF;
        --Column Privileges * End
    
        --Auditing options * Begin
        SELECT COUNT (*)
          INTO V_COUNTER
          FROM DBA_STMT_AUDIT_OPTS
         WHERE USER_NAME = V_USER;

        IF V_COUNTER > 0
        THEN
            DBMS_OUTPUT.PUT_LINE ('-- ' || V_COUNTER || ' auditing options');

            OPEN V_CURSOR FOR
                SELECT AUDIT_OPTION, SUCCESS, FAILURE
                  FROM DBA_STMT_AUDIT_OPTS
                 WHERE USER_NAME = V_USER;

            LOOP
                FETCH V_CURSOR
                INTO V_AUDIT_OPT, V_SUCCESS, V_FAILURE;

                EXIT WHEN V_CURSOR%NOTFOUND;

                IF V_SUCCESS <> 'NOT SET'
                THEN
                    DBMS_OUTPUT.PUT_LINE('AUDIT '||V_AUDIT_OPT||' BY '||V_NEW_USER||' '||V_SUCCESS||' WHENEVER SUCCESSFUL;');
                END IF;
                IF V_FAILURE <> 'NOT SET'
                THEN
                    DBMS_OUTPUT.PUT_LINE('AUDIT '||V_AUDIT_OPT||' BY '||V_NEW_USER||' '||V_FAILURE||' WHENEVER NOT SUCCESSFUL;');
                END IF;

            END LOOP;
            
            CLOSE V_CURSOR;
        END IF;
    --Auditing options * End

    ELSE
        DBMS_OUTPUT.PUT_LINE ('User ' || V_USER || ' does not exist.');
    END IF;
END;
/