-- Setzt das Demo-Schema DOAG_DOMAINS zurück: beendet offene Sitzungen und löscht den Benutzer samt allen Objekten.
-- Ausführen als SYS oder SYSTEM in FREEPDB1. Danach der Reihe nach: 01_benutzer.sql, pa_demo.pck, 02_wildwuchs.sql,
-- 04_ords.sql.

begin
  for lSitzung in (select sid, serial#
                     from v$session
                     where username = upper('doag_domains')) loop
    execute immediate 'alter system kill session ''' || lSitzung.sid || ',' || lSitzung.serial# || ''' immediate';
  end loop;
end;
/

drop user if exists doag_domains cascade;
