-- ORDS-Modul „folien“: Die Folien holen den Text eines Demo-Schritts und führen ihn per Knopf aus, unter
-- http://localhost:8080/ords/doag_domains/folien/...
--   GET  schritt/:nummer   Nummer, Art und Text des Schritts (aus pa_demo)
--   POST schritt/:nummer   führt den Schritt aus, Antwort als JSON mit ok, zeilen oder meldung
--   POST zuruecksetzen     stellt den Wildwuchs wieder her
-- Ausgeführt wird nur, was in pa_demo steht. POST nur von den lokal ausgelieferten Folien (http://localhost:8766).
-- Ausführen als DOAG_DOMAINS nach pa_demo.pck. Wiederholbar: define_module ersetzt das Modul samt Endpunkten.

begin
  ords.enable_schema(p_enabled => true,
                     p_schema => upper('doag_domains'),
                     p_url_mapping_type => 'BASE_PATH',
                     p_url_mapping_pattern => 'doag_domains',
                     p_auto_rest_auth => false);
  commit;
end;
/

begin
  ords.define_module(p_module_name => 'folien',
                     p_base_path => '/folien/',
                     p_items_per_page => 0,
                     p_status => 'PUBLISHED',
                     p_comments => 'Demo-Schritte für die Folien „Datenhygiene mit SQL Domains“');

  ords.set_module_origins_allowed(p_module_name => 'folien',
                                  p_origins_allowed => 'http://localhost:8766');

  ords.define_template(p_module_name => 'folien',
                       p_pattern => 'schritt/:nummer',
                       p_comments => 'Ein Demo-Schritt');

  ords.define_handler(p_module_name => 'folien',
                      p_pattern => 'schritt/:nummer',
                      p_method => 'GET',
                      p_source_type => ords.source_type_query_one_row,
                      p_source => q'~
select :nummer as nummer,
       pa_demo.schrittArt(:nummer) as art,
       pa_demo.schrittText(:nummer) as anweisung~',
                      p_comments => 'Nummer, Art und Text des Schritts');

  ords.define_handler(p_module_name => 'folien',
                      p_pattern => 'schritt/:nummer',
                      p_method => 'POST',
                      p_source_type => ords.source_type_plsql,
                      p_source => q'~
begin
  pa_demo.antworten(pa_demo.ausfuehren(:nummer));
end;~',
                      p_comments => 'Führt den Schritt aus');

  ords.define_template(p_module_name => 'folien',
                       p_pattern => 'zuruecksetzen',
                       p_comments => 'Wildwuchs wiederherstellen');

  ords.define_handler(p_module_name => 'folien',
                      p_pattern => 'zuruecksetzen',
                      p_method => 'POST',
                      p_source_type => ords.source_type_plsql,
                      p_source => q'~
begin
  pa_demo.zuruecksetzen;
  pa_demo.antworten('{"ok":true,"meldung":"Wildwuchs wiederhergestellt"}');
end;~',
                      p_comments => 'Stellt Tabellen und Daten des Wildwuchses wieder her');

  commit;
end;
/
