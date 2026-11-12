create or replace package pa_demo authid current_user is
  -- Demo-Schritte des Vortrags „Datenhygiene mit SQL Domains“. Die Folien zeigen den Text eines Schritts und führen ihn
  -- per Knopf über ORDS aus (Modul „folien“ in 04_ords.sql). Jeder Schritt steht nur hier.
  -- Invoker Rights, damit DDL über die Rolle db_developer_role erlaubt ist.

  -- Art des Schritts: abfrage, befehl oder block
  function schrittArt(pNummer varchar2) return varchar2;

  -- Anweisung des Schritts, so wie sie auf der Folie steht
  function schrittText(pNummer varchar2) return clob;

  -- führt den Schritt aus und liefert JSON: {nummer, art, ok, zeilen} bei Abfragen, {nummer, art, ok, meldung} sonst;
  -- Fehler kommen als ok = false mit der Oracle-Meldung zurück, sie sind in der Demo gewollt
  function ausfuehren(pNummer varchar2) return clob;

  -- schreibt JSON als HTTP-Antwort (für die ORDS-Handler)
  procedure antworten(pJson clob);

  -- stellt den Wildwuchs wieder her: löscht Tabellen und Domains des Vortrags und legt Tabellen und Daten neu an
  procedure zuruecksetzen;
end;
/
create or replace package body pa_demo is

  type tSchritt is record (
    art   varchar2(10),
    text  clob
  );
  type tSchritte is table of tSchritt index by varchar2(10);
  gSchritte tSchritte;

  -- Forward Declarations
  procedure fuellen;

  ----------------------------------------------------------------------------------------------------------------------
  function schrittArt(pNummer varchar2) return varchar2 is begin
    fuellen;
    return case when gSchritte.exists(pNummer) then gSchritte(pNummer).art end;
  end;

  ----------------------------------------------------------------------------------------------------------------------
  function schrittText(pNummer varchar2) return clob is begin
    fuellen;
    return case when gSchritte.exists(pNummer) then gSchritte(pNummer).text end;
  end;

  ----------------------------------------------------------------------------------------------------------------------
  -- Meldung nach einem erfolgreichen Befehl oder Block, angelehnt an SQL*Plus
  function meldung(pText clob, pAnzahl integer) return varchar2 is
    lVerb varchar2(20) := lower(regexp_substr(pText, '^\s*(\w+)', 1, 1, null, 1));
    lZeilen varchar2(20) := pAnzahl || case when pAnzahl = 1 then ' Zeile' else ' Zeilen' end;
  begin
    return case
             when lVerb = 'insert' then lZeilen || ' eingefügt'
             when lVerb = 'update' then lZeilen || ' aktualisiert'
             when lVerb = 'delete' then lZeilen || ' gelöscht'
             when lVerb in ('declare', 'begin') then 'PL/SQL-Block erfolgreich abgeschlossen'
             else 'Erfolgreich ausgeführt'
           end;
  end;

  ----------------------------------------------------------------------------------------------------------------------
  function ausfuehren(pNummer varchar2) return clob is
    lErgebnis json_object_t := json_object_t();
    lSchritt  tSchritt;
    lZeilen   clob;
    lAnzahl   integer;
  begin
    fuellen;
    lErgebnis.put('nummer', pNummer);
    if not gSchritte.exists(pNummer) then
      lErgebnis.put('ok', false);
      lErgebnis.put('meldung', 'Unbekannter Schritt ' || pNummer);
      return lErgebnis.to_clob;
    end if;

    lSchritt := gSchritte(pNummer);
    lErgebnis.put('art', lSchritt.art);
    -- deutsche Fehlermeldungen wie im Vortrag, unabhängig von den Einstellungen der ORDS-Sitzung
    dbms_session.set_nls('nls_language', '''GERMAN''');

    if lSchritt.art = 'abfrage' then
      execute immediate 'select json_arrayagg(json_object(* returning clob) order by rownum returning clob) from ('
                        || lSchritt.text || ')'
        into lZeilen;
      lErgebnis.put('ok', true);
      lErgebnis.put('zeilen', json_array_t.parse(nvl(lZeilen, to_clob('[]'))));
    else
      execute immediate lSchritt.text;
      lAnzahl := sql%rowcount;
      commit;
      lErgebnis.put('ok', true);
      lErgebnis.put('meldung', meldung(lSchritt.text, lAnzahl));
    end if;
    return lErgebnis.to_clob;
  exception
    when others then
      rollback;
      lErgebnis.put('ok', false);
      lErgebnis.put('meldung', rtrim(dbms_utility.format_error_stack, chr(10)));
      return lErgebnis.to_clob;
  end;

  ----------------------------------------------------------------------------------------------------------------------
  procedure antworten(pJson clob) is
    lcStueck constant integer := 4000;
  begin
    owa_util.mime_header('application/json', true, 'UTF-8');
    for i in 0 .. trunc((dbms_lob.getlength(pJson) - 1) / lcStueck) loop
      htp.prn(dbms_lob.substr(pJson, lcStueck, i * lcStueck + 1));
    end loop;
  end;

  ----------------------------------------------------------------------------------------------------------------------
  procedure zuruecksetzen is
    procedure ausfuehrenStill(pText varchar2) is begin
      execute immediate pText;
    end;
  begin
    ausfuehrenStill('drop table if exists stoerung purge');
    ausfuehrenStill('drop table if exists leitung purge');
    ausfuehrenStill('drop table if exists fahrzeug purge');
    ausfuehrenStill('drop table if exists mitarbeiter purge');
    ausfuehrenStill('drop table if exists lieferant purge');
    ausfuehrenStill('drop table if exists kunde purge');

    -- Domains, die im Vortrag entstehen
    ausfuehrenStill('drop domain if exists email_d force');
    ausfuehrenStill('drop domain if exists kennzeichen_d force');
    ausfuehrenStill('drop domain if exists stoerung_status_enum force');
    ausfuehrenStill('drop domain if exists spannungsebene_enum force');

    -- E-Mail mit strengem Check, Telefonnummer ungeprüft
    ausfuehrenStill(q'~
create table kunde (
  kunde_id  integer generated by default as identity annotations (description 'Primärschlüssel'),
  name      varchar2(100) not null annotations (description 'Vor- und Nachname'),
  email     varchar2(200) annotations (description 'E-Mail-Adresse'),
  telefon   varchar2(50) annotations (description 'Telefonnummer in beliebiger Schreibweise'),
  constraint pk_kunde   primary key (kunde_id),
  constraint chk1_kunde check (regexp_like(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'))
)
annotations (description 'Kunden des Stadtwerks')~');

    -- E-Mail mit laxem Check und Trigger, der in Kleinbuchstaben umwandelt
    ausfuehrenStill(q'~
create table lieferant (
  lieferant_id  integer generated by default as identity annotations (description 'Primärschlüssel'),
  firma         varchar2(100) not null annotations (description 'Name der Firma'),
  email         varchar2(100) annotations (description 'E-Mail-Adresse für Bestellungen'),
  telefon       varchar2(30) annotations (description 'Telefonnummer der Zentrale'),
  constraint pk_lieferant   primary key (lieferant_id),
  constraint chk1_lieferant check (email like '%@%.%')
)
annotations (description 'Lieferanten des Stadtwerks')~');

    ausfuehrenStill(q'~
create or replace trigger tbiu_lieferant
  before insert or update of email on lieferant
  for each row
  begin
    :new.email := lower(:new.email);
  end;~');

    -- E-Mail ganz ohne Constraint, „das prüft die Anwendung“
    ausfuehrenStill(q'~
create table mitarbeiter (
  mitarbeiter_id  integer generated by default as identity annotations (description 'Primärschlüssel'),
  name            varchar2(100) not null annotations (description 'Vor- und Nachname'),
  email           varchar2(255) annotations (description 'Dienstliche E-Mail-Adresse'),
  constraint pk_mitarbeiter primary key (mitarbeiter_id)
)
annotations (description 'Mitarbeiter des Stadtwerks')~');

    -- Kennzeichen in gemischter Schreibweise
    ausfuehrenStill(q'~
create table fahrzeug (
  fahrzeug_id     integer generated by default as identity annotations (description 'Primärschlüssel'),
  kennzeichen     varchar2(15) not null annotations (description 'Amtliches Kennzeichen'),
  mitarbeiter_id  integer annotations (description 'Mitarbeiter, dem das Fahrzeug zugeordnet ist'),
  constraint pk_fahrzeug  primary key (fahrzeug_id),
  constraint fk1_fahrzeug foreign key (mitarbeiter_id) references mitarbeiter (mitarbeiter_id)
)
annotations (description 'Fuhrpark des Stadtwerks')~');

    ausfuehrenStill('create index if1_fahrzeug on fahrzeug (mitarbeiter_id)');

    -- Spannungsebene als Freitext
    ausfuehrenStill(q'~
create table leitung (
  leitung_id      integer generated by default as identity annotations (description 'Primärschlüssel'),
  bezeichnung     varchar2(100) not null annotations (description 'Name der Leitung'),
  spannungsebene  varchar2(30) annotations (description 'Spannungsebene der Leitung'),
  constraint pk_leitung primary key (leitung_id)
)
annotations (description 'Stromleitungen im Netz des Stadtwerks')~');

    -- Status als Werteliste in gemischter Schreibweise
    ausfuehrenStill(q'~
create table stoerung (
  stoerung_id   integer generated by default as identity annotations (description 'Primärschlüssel'),
  leitung_id    integer not null annotations (description 'Betroffene Leitung'),
  gemeldet_am   date not null annotations (description 'Zeitpunkt der Meldung'),
  beschreibung  varchar2(200) annotations (description 'Was gemeldet wurde'),
  status        varchar2(20) not null annotations (description 'Bearbeitungsstand'),
  constraint pk_stoerung   primary key (stoerung_id),
  constraint fk1_stoerung  foreign key (leitung_id) references leitung (leitung_id),
  constraint chk1_stoerung check (status in ('neu', 'NEU', 'in Arbeit', 'erledigt', 'Erledigt'))
)
annotations (description 'Störungsmeldungen im Stromnetz')~');

    ausfuehrenStill('create index if1_stoerung on stoerung (leitung_id)');

    -- Daten: alle Personen, Firmen, Adressen und Nummern sind erfunden; E-Mail-Adressen nur unter den reservierten
    -- Domains example.com, example.org, example.net und *.example

    -- Kunden: Die E-Mail-Adressen erfüllen den strengen Check, die Telefonnummern stehen in jeder denkbaren Schreibweise.
    ausfuehrenStill(q'~
insert into kunde (name, email, telefon)
  values ('Anna Schmidt',      'Anna.Schmidt@example.com',        '0911 123456'),
         ('Bernd Müller',      'bernd.mueller@example.org',       '0911/234567'),
         ('Carla Weber',       'carla.weber@example.net',         '+49 911 345678'),
         ('Dieter Fischer',    'DIETER.FISCHER@EXAMPLE.COM',      '(0911) 456789'),
         ('Elke Wagner',       'elke.wagner@example.org',         '0911-56 78 90'),
         ('Frank Becker',      'f.becker@example.com',            '+49 (0)911 678901'),
         ('Gisela Hoffmann',   'gisela.hoffmann@example.net',     '0049911789012'),
         ('Hans Schäfer',      'hans.schaefer@example.com',       '0171 2345678'),
         ('Ingrid Koch',       'ingrid.koch@example.org',         '+49 171 3456789'),
         ('Jürgen Bauer',      'juergen.bauer@example.net',       'folgt'),
         ('Karin Richter',     'karin_richter@example.com',       '0911'),
         ('Lars Klein',        'lars.klein+strom@example.org',    null),
         ('Monika Wolf',       'monika.wolf@example.com',         '0911 890123 '),
         ('Norbert Schröder',  'norbert.schroeder@example.net',   '09 11 / 90 12 34'),
         ('Olga Neumann',      'olga.neumann@example.org',        '+49-911-012345'),
         ('Peter Schwarz',     null,                              '0911 135791'),
         ('Renate Zimmermann', 'renate.zimmermann@example.com',   '0911 246802'),
         ('Stefan Braun',      'stefan.braun@example.net',        '0911.357913'),
         ('Tanja Krüger',      'tanja.krueger@example.org',       '+49 911 468024'),
         ('Uwe Hofmann',       'uwe.hofmann@example.com',         '0160 97531')~');

    -- Lieferanten: Der laxe Check lässt Leerzeichen, zwei Adressen und eine fehlende Endung durch; der Trigger schreibt
    -- alles klein.
    ausfuehrenStill(q'~
insert into lieferant (firma, email, telefon)
  values ('Elektro Meier GmbH',   'Bestellung@Elektro-Meier.example',                         '0911 112233'),
         ('Kabelwerk Franken AG', 'info@kabelwerk-franken.example',                           '+49 911 223344'),
         ('Schmitz Tiefbau',      'info @schmitz-tiefbau.example',                            '0911/334455'),
         ('Trafo-Service Süd',    'service@trafo-sued.example; rechnung@trafo-sued.example',  '0911 445566'),
         ('Bürobedarf Hofmann',   'buero@hofmann.example',                                    '0911-556677'),
         ('Messtechnik Berger',   'kontakt@messtechnik-berger.example',                       '(0911) 667788'),
         ('Netzbau Ost',          'auftrag@netzbau-ost.',                                     '0911 778899'),
         ('Arbeitsschutz Lang',   'vertrieb@lang-arbeitsschutz.example',                      '+49 911 889900'),
         ('Werkzeug Kraus',       'kraus@werkzeug-kraus.example',                             '0911 990011'),
         ('IT-Haus Nürnberg',     'support@it-haus.example',                                  '0911 101010')~');

    -- Mitarbeiter: kein Constraint, „das prüft die Anwendung“.
    ausfuehrenStill(q'~
insert into mitarbeiter (name, email)
  values ('Klaus Meier',     'k.meier(at)stadtwerk.example'),
         ('Thomas Huber',    't.huber@stadtwerk'),
         ('Sabine Wagner',   '  s.wagner@stadtwerk.example'),
         ('Michael Lehmann', 'm.lehmann@stadtwerk.example'),
         ('Julia Schulz',    'J.Schulz@Stadtwerk.example'),
         ('Andreas Keller',  'a.keller@stadtwerk.example'),
         ('Petra Hahn',      null),
         ('Markus Vogel',    'Hausmeister'),
         ('Claudia Frank',   'c.frank@stadtwerk.example'),
         ('Martin Roth',     'm.roth@@stadtwerk.example'),
         ('Nicole Beck',     'n.beck@stadtwerk.example'),
         ('Tobias Lorenz',   't.lorenz@stadtwerk.example'),
         ('Sandra Busch',    's.busch@stadtwerk,example'),
         ('Daniel Jung',     'd.jung@stadtwerk.example'),
         ('Heike Pohl',      'h.pohl@stadtwerk.example ')~');

    -- Fahrzeuge: Kennzeichen mit und ohne Bindestrich, mit Leerzeichen an allen Stellen, klein geschrieben.
    ausfuehrenStill(q'~
insert into fahrzeug (kennzeichen, mitarbeiter_id)
  select f.kennzeichen, m.mitarbeiter_id
    from (values ('N-SW 101',   'Klaus Meier'),
                 ('N SW 102',   'Thomas Huber'),
                 ('n-sw-103',   'Sabine Wagner'),
                 ('N-SW104',    'Michael Lehmann'),
                 ('N - SW 105', 'Andreas Keller'),
                 ('N-SW 106E',  'Claudia Frank'),
                 ('N-SW 107',   'Martin Roth'),
                 ('NSW 108',    'Tobias Lorenz'),
                 ('N-SW 109 ',  'Daniel Jung'),
                 ('FÜ-SW 110',  'Heike Pohl'),
                 ('N-SW-111',   'Markus Vogel'),
                 ('N-SW 112',   null)) f (kennzeichen, mitarbeiter)
    left join mitarbeiter m
      on m.name = f.mitarbeiter~');

    -- Leitungen: dieselbe Spannungsebene in vielen Schreibweisen, eine Leitung ohne Angabe, eine mit zwei Ebenen.
    ausfuehrenStill(q'~
insert into leitung (bezeichnung, spannungsebene)
  values ('Kabel Gostenhof 1',          'NS'),
         ('Kabel Gostenhof 2',          'Niederspannung'),
         ('Kabel St. Johannis',         '0,4 kV'),
         ('Kabel Wöhrd',                '0.4kV'),
         ('Kabel Maxfeld',              'ns'),
         ('Ring Nord',                  'MS'),
         ('Ring Süd',                   'Mittelspannung'),
         ('Abgang Umspannwerk West 3',  '20 kV'),
         ('Abgang Umspannwerk West 4',  '20kV'),
         ('Ring Ost',                   'mittel'),
         ('Freileitung Fischbach',      'HS'),
         ('Freileitung Reichswald',     '110 kV'),
         ('Freileitung Altenfurt',      'Hochspannung'),
         ('Kabel Hafen',                null),
         ('Station Solarpark Süd',      'MS/NS')~');

    -- Störungen: Status aus der Werteliste in gemischter Schreibweise.
    ausfuehrenStill(q'~
insert into stoerung (leitung_id, gemeldet_am, beschreibung, status)
  select l.leitung_id, s.gemeldet_am, s.beschreibung, s.status
    from (values ('Kabel Gostenhof 1',         timestamp '2026-10-01 07:42:00', 'Stromausfall in drei Häusern',          'erledigt'),
                 ('Ring Nord',                 timestamp '2026-10-01 11:05:00', 'Spannungseinbruch',                     'Erledigt'),
                 ('Freileitung Fischbach',     timestamp '2026-10-02 06:18:00', 'Baum auf Freileitung',                  'erledigt'),
                 ('Kabel Wöhrd',               timestamp '2026-10-02 14:30:00', 'Flackerndes Licht',                     'Erledigt'),
                 ('Abgang Umspannwerk West 3', timestamp '2026-10-03 09:12:00', 'Kabelschaden durch Bagger',             'erledigt'),
                 ('Kabel Maxfeld',             timestamp '2026-10-05 19:47:00', 'Sicherung im Kabelverteiler ausgelöst', 'erledigt'),
                 ('Ring Süd',                  timestamp '2026-10-06 08:03:00', 'Geräusche am Trafo',                    'Erledigt'),
                 ('Station Solarpark Süd',     timestamp '2026-10-07 12:55:00', 'Wechselrichter abgeschaltet',           'erledigt'),
                 ('Kabel St. Johannis',        timestamp '2026-10-08 16:20:00', 'Stromausfall in einer Straße',          'erledigt'),
                 ('Freileitung Reichswald',    timestamp '2026-10-09 05:36:00', 'Vogel im Umspannwerk',                  'Erledigt'),
                 ('Kabel Gostenhof 2',         timestamp '2026-10-12 10:10:00', 'Überspannung gemeldet',                 'erledigt'),
                 ('Ring Ost',                  timestamp '2026-10-13 13:44:00', 'Kurzschluss im Kabelverteiler',         'erledigt'),
                 ('Kabel Hafen',               timestamp '2026-10-14 07:01:00', 'Stromausfall im Hafengebiet',           'Erledigt'),
                 ('Abgang Umspannwerk West 4', timestamp '2026-10-15 15:27:00', 'Spannungseinbruch',                     'erledigt'),
                 ('Freileitung Altenfurt',     timestamp '2026-10-16 03:58:00', 'Baum auf Freileitung',                  'erledigt'),
                 ('Kabel Gostenhof 1',         timestamp '2026-10-19 08:22:00', 'Flackerndes Licht',                     'in Arbeit'),
                 ('Ring Nord',                 timestamp '2026-10-20 17:09:00', 'Geräusche am Trafo',                    'in Arbeit'),
                 ('Kabel Wöhrd',               timestamp '2026-10-21 12:40:00', 'Stromausfall in drei Häusern',          'in Arbeit'),
                 ('Freileitung Fischbach',     timestamp '2026-10-22 06:51:00', 'Isolator beschädigt',                   'in Arbeit'),
                 ('Station Solarpark Süd',     timestamp '2026-10-23 11:33:00', 'Einspeisung schwankt',                  'in Arbeit'),
                 ('Kabel Maxfeld',             timestamp '2026-10-26 09:15:00', 'Sicherung im Kabelverteiler ausgelöst', 'in Arbeit'),
                 ('Ring Süd',                  timestamp '2026-10-26 14:02:00', 'Spannungseinbruch',                     'neu'),
                 ('Kabel St. Johannis',        timestamp '2026-10-27 07:48:00', 'Stromausfall in einer Straße',          'NEU'),
                 ('Abgang Umspannwerk West 3', timestamp '2026-10-27 10:26:00', 'Kabelschaden durch Bagger',             'neu'),
                 ('Kabel Gostenhof 2',         timestamp '2026-10-27 18:31:00', 'Flackerndes Licht',                     'NEU'),
                 ('Freileitung Reichswald',    timestamp '2026-10-28 05:12:00', 'Baum auf Freileitung',                  'neu'),
                 ('Ring Ost',                  timestamp '2026-10-28 13:57:00', 'Überspannung gemeldet',                 'neu'),
                 ('Kabel Hafen',               timestamp '2026-10-28 16:40:00', 'Kurzschluss im Kabelverteiler',         'NEU'),
                 ('Freileitung Altenfurt',     timestamp '2026-10-29 06:24:00', 'Vogel im Umspannwerk',                  'neu'),
                 ('Kabel Gostenhof 1',         timestamp '2026-10-29 08:05:00', 'Stromausfall in drei Häusern',          'NEU')
         ) s (leitung, gemeldet_am, beschreibung, status)
    join leitung l
      on l.bezeichnung = s.leitung~');

    commit;
  end;

  ----------------------------------------------------------------------------------------------------------------------
  -- legt einen Schritt an; führende Leerzeilen und Wagenrückläufe fallen weg
  procedure neu(pNummer varchar2, pArt varchar2, pText varchar2) is begin
    gSchritte(pNummer).art := pArt;
    gSchritte(pNummer).text := ltrim(replace(pText, chr(13)), chr(10));
  end;

  ----------------------------------------------------------------------------------------------------------------------
  -- alle Schritte in der Reihenfolge des Vortrags; Nummer = Abschnitt.laufende Nummer
  procedure fuellen is
  begin
    if gSchritte.count > 0 then return; end if;

    -- Abschnitt 2: Der Wildwuchs ------------------------------------------------------------------------------------
    neu('2.1', 'abfrage', q'~
select c.table_name as tabelle,
       c.data_type || '(' || c.char_length || ')' as typ,
       c.domain_name as domain,
       k.search_condition_vc as check_constraint,
       t.trigger_name
  from user_tab_cols c
  left join user_constraints k
    on k.table_name = c.table_name
    and k.constraint_type = 'C'
    and k.domain_name is null
    and upper(k.search_condition_vc) like '%EMAIL%'
    and upper(k.search_condition_vc) not like '%IS NOT NULL'
  left join user_trigger_cols t
    on t.table_name = c.table_name
    and t.column_name = c.column_name
  where c.column_name = 'EMAIL'
  order by c.table_name~');

    neu('2.2', 'abfrage', q'~
select 'lieferant' as tabelle, email
  from lieferant
  where not regexp_like(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
union all
select 'mitarbeiter', email
  from mitarbeiter
  where not regexp_like(email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')~');

    neu('2.3', 'abfrage', q'~
select count(*) as leitungen,
       count(distinct spannungsebene) as schreibweisen
  from leitung~');

    -- Abschnitt 4: Die erste Domain: E-Mail ------------------------------------------------------------------------
    neu('4.1', 'befehl', q'~
create domain email_d as varchar2(320 char)
  constraint chk1_email_d check (regexp_like(value, '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$', 'i'))
  display lower(value)
  order regexp_replace(lower(value), '^(.*)@(.*)$', '\2 \1')
  annotations (description 'E-Mail-Adresse')~');

    neu('4.2', 'befehl', q'~
alter table kunde modify (email domain email_d)~');

    neu('4.3', 'abfrage', q'~
select table_name as tabelle,
       column_name as spalte,
       domain_name as domain
  from user_tab_cols
  where column_name = 'EMAIL'
  order by table_name~');

    -- mit from-Klausel: json_object(*) über domain_check ohne from beendet auf 23.26 den Serverprozess (ORA-03113)
    neu('4.4', 'abfrage', q'~
select a.adresse,
       domain_check(email_d, a.adresse) as gueltig
  from (values ('k.meier(at)stadtwerk.example'), ('anna.schmidt@example.com')) a (adresse)~');

    neu('4.5', 'befehl', q'~
insert into kunde (name, email)
  values ('Neuer Kunde', 'k.meier(at)stadtwerk.example')~');

    neu('4.6', 'abfrage', q'~
select email,
       domain_display(email) as anzeige
  from kunde
  where email is not null
  order by domain_order(email)~');

    -- Abschnitt 5: Weitere Wertebereiche ---------------------------------------------------------------------------
    neu('5.1', 'abfrage', q'~
select count(*) as mitgeliefert
  from all_domains
  where owner = 'SYS'~');

    neu('5.2', 'abfrage', q'~
select d.name as domain,
       c.search_condition as regel
  from all_domains d
  left join all_domain_constraints c
    on c.domain_owner = d.owner
    and c.domain_name = d.name
  where d.owner = 'SYS'
    and d.name in ('EMAIL_D', 'PHONE_NUMBER_D', 'LICENSE_PLATE_D', 'US_LICENSE_PLATE_D')
  order by d.name~');

    neu('5.3', 'abfrage', q'~
select telefon,
       domain_check(sys.phone_number_d, telefon) as phone_number_d
  from kunde
  order by kunde_id~');

    neu('5.4', 'befehl', q'~
create domain kennzeichen_d as varchar2(15 char)
  constraint chk1_kennzeichen_d check (regexp_like(value, '^[[:upper:]]{1,3}-[[:upper:]]{1,2} [1-9][0-9]{0,3}[EH]?$'))
  annotations (description 'Amtliches Kennzeichen in Deutschland')~');

    neu('5.5', 'abfrage', q'~
select kennzeichen,
       domain_check(kennzeichen_d, kennzeichen) as kennzeichen_d,
       domain_check(sys.us_license_plate_d, kennzeichen) as us_license_plate_d
  from fahrzeug
  order by kennzeichen~');

    -- Abschnitt 6: Bestehende Tabellen migrieren -------------------------------------------------------------------
    neu('6.1', 'befehl', q'~
alter table mitarbeiter modify (email domain email_d)~');

    neu('6.2', 'abfrage', q'~
select 'lieferant' as tabelle, email
  from lieferant
  where not domain_check(email_d, email)
union all
select 'mitarbeiter', email
  from mitarbeiter
  where not domain_check(email_d, email)~');

    neu('6.3', 'befehl', q'~
update mitarbeiter
  set email = regexp_replace(replace(replace(trim(email), '(at)', '@'), '@@', '@'),
                             '@stadtwerk(,example)?$', '@stadtwerk.example')
  where not domain_check(email_d, email)~');

    neu('6.4', 'befehl', q'~
update lieferant
  set email = regexp_substr(replace(email, ' @', '@'), '[^; ]+')
  where not domain_check(email_d, email)~');

    neu('6.5', 'befehl', q'~
update mitarbeiter
  set email = null
  where email = 'Hausmeister'~');

    neu('6.6', 'befehl', q'~
update lieferant
  set email = 'auftrag@netzbau-ost.example'
  where email = 'auftrag@netzbau-ost.'~');

    neu('6.7', 'befehl', q'~
alter table mitarbeiter modify (email domain email_d)~');

    neu('6.8', 'befehl', q'~
alter table lieferant modify (email domain email_d)~');

    neu('6.9', 'abfrage', q'~
select table_name as tabelle,
       constraint_name,
       domain_name as domain
  from user_constraints
  where domain_name is not null
  order by table_name~');

    -- auch in Abschnitt 10: alte Checks ohne Domain auf Spalten, die schon eine Domain haben
    neu('6.10', 'abfrage', q'~
select c.table_name as tabelle,
       c.constraint_name,
       t.column_name as spalte,
       t.domain_name as domain
  from user_constraints c
  join user_cons_columns cc
    on cc.constraint_name = c.constraint_name
  join user_tab_cols t
    on t.table_name = cc.table_name
    and t.column_name = cc.column_name
  where c.constraint_type = 'C'
    and c.domain_name is null
    and t.domain_name is not null
    and c.search_condition_vc not like '%IS NOT NULL'
  order by c.table_name~');

    neu('6.11', 'befehl', q'~
alter table kunde drop constraint chk1_kunde~');

    neu('6.12', 'befehl', q'~
alter table lieferant drop constraint chk1_lieferant~');

    neu('6.13', 'befehl', q'~
drop trigger tbiu_lieferant~');

    -- Abschnitt 7: Enum-Domains ------------------------------------------------------------------------------------
    neu('7.1', 'befehl', q'~
create domain stoerung_status_enum as enum (
  neu       = 'neu',
  in_arbeit = 'in Arbeit',
  erledigt  = 'erledigt'
)~');

    neu('7.2', 'abfrage', q'~
select *
  from stoerung_status_enum~');

    -- der lehrreiche Fehlversuch: lower('in Arbeit') steht nicht in der alten Werteliste
    neu('7.3', 'befehl', q'~
update stoerung
  set status = lower(status)
  where status <> lower(status)~');

    neu('7.4', 'befehl', q'~
update stoerung
  set status = lower(status)
  where status in ('NEU', 'Erledigt')~');

    neu('7.5', 'befehl', q'~
alter table stoerung modify (status domain stoerung_status_enum)~');

    neu('7.6', 'befehl', q'~
alter table stoerung drop constraint chk1_stoerung~');

    neu('7.7', 'befehl', q'~
insert into stoerung (leitung_id, gemeldet_am, beschreibung, status)
  select leitung_id, sysdate, 'Kabelschaden', 'storniert'
    from leitung
    where bezeichnung = 'Ring Nord'~');

    neu('7.8', 'abfrage', q'~
select status,
       domain_display(status) as anzeige,
       domain_order(status) as sortierung,
       count(*) as anzahl
  from stoerung
  group by status, domain_display(status), domain_order(status)
  order by domain_order(status)~');

    neu('7.9', 'befehl', q'~
alter domain stoerung_status_enum
  modify order case stoerung_status_enum
                 when 'neu' then 1
                 when 'in Arbeit' then 2
                 when 'erledigt' then 3
               end~');

    neu('7.10', 'befehl', q'~
create domain spannungsebene_enum as enum (
  niederspannung = ns = 'NS',
  mittelspannung = ms = 'MS',
  hochspannung   = hs = 'HS'
)~');

    neu('7.11', 'abfrage', q'~
select spannungsebene,
       case
         when upper(replace(spannungsebene, ' ')) in ('NS', 'NIEDERSPANNUNG', '0,4KV', '0.4KV') then spannungsebene_enum.ns
         when upper(replace(spannungsebene, ' ')) in ('MS', 'MITTELSPANNUNG', '20KV', 'MITTEL') then spannungsebene_enum.ms
         when upper(replace(spannungsebene, ' ')) in ('HS', 'HOCHSPANNUNG', '110KV') then spannungsebene_enum.hs
       end as ebene
  from leitung
  order by 2, 1~');

    neu('7.12', 'abfrage', q'~
select *
  from spannungsebene_enum~');

    -- Abschnitt 8: Stolpersteine -----------------------------------------------------------------------------------
    neu('8.1', 'abfrage', q'~
select count(*) as anzahl
  from stoerung
  where status = stoerung_status_enum.storniert~');

    neu('8.2', 'befehl', q'~
insert into stoerung (leitung_id, gemeldet_am, beschreibung, status)
  values (1, sysdate, 'Kabelschaden', stoerung_status_enum.storniert)~');

    neu('8.3', 'block', q'~
declare
  lStatus varchar2(20);
begin
  lStatus := stoerung_status_enum.neu;
end;~');

    neu('8.4', 'block', q'~
declare
  procedure pruefeEmail(pEmail email_d) is
  begin
    null;
  end;
begin
  null;
end;~');

    neu('8.5', 'block', q'~
declare
  lEmail kunde.email%type := 'Hausmeister';
begin
  null;
end;~');

    neu('8.6', 'block', q'~
declare
  lEmail   kunde.email%type := 'Hausmeister';
  lGueltig boolean;
begin
  select domain_check(email_d, lEmail) into lGueltig;
  if not lGueltig then
    raise_application_error(-20001, 'Keine gültige E-Mail-Adresse: ' || lEmail);
  end if;
end;~');

    -- Abschnitt 9: Domains weiterentwickeln ------------------------------------------------------------------------
    neu('9.1', 'befehl', q'~
alter domain stoerung_status_enum add storniert = 'storniert'~');

    neu('9.2', 'befehl', q'~
drop domain stoerung_status_enum~');

    neu('9.3', 'abfrage', q'~
select dbms_metadata.get_ddl('SQL_DOMAIN', 'STOERUNG_STATUS_ENUM') as ddl~');

    neu('9.4', 'befehl', q'~
drop domain stoerung_status_enum force preserve~');

    neu('9.5', 'abfrage', q'~
select constraint_name,
       domain_name as domain,
       search_condition_vc as bedingung
  from user_constraints
  where table_name = 'STOERUNG'
    and constraint_type = 'C'
    and search_condition_vc not like '%IS NOT NULL'
  order by constraint_name~');

    neu('9.6', 'befehl', q'~
create domain stoerung_status_enum as enum (
  neu       = 'neu',
  in_arbeit = 'in Arbeit',
  erledigt  = 'erledigt',
  storniert = 'storniert'
)~');

    neu('9.7', 'befehl', q'~
alter domain stoerung_status_enum
  modify order case stoerung_status_enum
                 when 'neu' then 1
                 when 'in Arbeit' then 2
                 when 'erledigt' then 3
                 when 'storniert' then 4
               end~');

    neu('9.8', 'befehl', q'~
alter table stoerung modify (status domain stoerung_status_enum)~');

    neu('9.9', 'befehl', q'~
update stoerung
  set status = stoerung_status_enum.storniert
  where beschreibung = 'Vogel im Umspannwerk'
    and status = stoerung_status_enum.neu~');

    -- Abschnitt 10: Wer ist betroffen? -----------------------------------------------------------------------------
    neu('10.1', 'abfrage', q'~
select table_name as tabelle,
       column_name as spalte,
       domain_owner,
       domain_name as domain
  from user_tab_cols
  where domain_name is not null
  order by domain_name, table_name~');

    neu('10.2', 'abfrage', q'~
select name as tabelle,
       referenced_name as domain
  from user_dependencies
  where referenced_type = 'DOMAIN'
  order by referenced_name, name~');

    -- löscht, was die Abfrage 6.10 findet: die von force preserve bewahrten Checks
    neu('10.3', 'block', q'~
begin
  for lAltlast in (select c.table_name, c.constraint_name
                     from user_constraints c
                     join user_cons_columns cc
                       on cc.constraint_name = c.constraint_name
                     join user_tab_cols t
                       on t.table_name = cc.table_name
                       and t.column_name = cc.column_name
                     where c.constraint_type = 'C'
                       and c.domain_name is null
                       and t.domain_name is not null
                       and c.search_condition_vc not like '%IS NOT NULL') loop
    execute immediate 'alter table ' || lAltlast.table_name || ' drop constraint ' || lAltlast.constraint_name;
  end loop;
end;~');
  end;

end;
/
