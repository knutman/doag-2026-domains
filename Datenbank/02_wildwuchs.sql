-- Ausgangslage des Vortrags „Datenhygiene mit SQL Domains“: das Schema eines erfundenen Stadtwerks, über die Jahre von
-- verschiedenen Teams gewachsen. Dieselben fachlichen Regeln stehen absichtlich an mehreren Stellen und jedes Mal anders
-- da: als strenger Check, als laxer Check, als Trigger, gar nicht (die Anwendung prüft angeblich) oder als Werteliste
-- in gemischter Schreibweise.
-- Tabellen und Daten stehen in pa_demo.zuruecksetzen, damit der Knopf „Zurücksetzen“ der Folien dasselbe tut.
-- Ausführen als DOAG_DOMAINS nach pa_demo.pck; wiederholbar, löscht vorher alle Tabellen und Domains des Vortrags.

begin
  pa_demo.zuruecksetzen;
end;
/
