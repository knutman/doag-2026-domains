-- Legt den Demo-Benutzer DOAG_DOMAINS an.
-- Ausführen als SYS oder SYSTEM in FREEPDB1. Das Kennwort fragt das Skript beim Ausführen ab.
-- db_developer_role enthält create domain sowie über RESOURCE Tabellen und Trigger.

create user doag_domains identified by "&kennwort_doag_domains"
  default tablespace users
  quota unlimited on users;

grant db_developer_role to doag_domains;
