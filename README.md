# „Wollen wir mal sauber machen?“ – Datenhygiene mit SQL Domains

Begleitmaterial zum Vortrag auf der DOAG 2026 in Nürnberg.

- **Termin:** Donnerstag, 19.11.2026, 15:00–15:45, Raum Budapest
- **Vortragender:** Knut Göttling (Enignum AI)
- **Format:** Standard Session (45 Min.), Einstieg, Schwerpunkt Coding

## Abstract

Datenqualität verteilt sich in vielen Schemata über dutzende, oft widersprüchliche Check-Constraints, Trigger und
Anwendungslogik. Mit 23ai hat Oracle die Data Use Case Domains eingeführt – ein Dictionary-Objekt, das Datentyp,
Constraints, Default, Display- und Order-Format sowie Annotations zentral kapselt und auf beliebig viele Spalten
anwendbar macht. Das Feature wird in der Praxis kaum genutzt, obwohl es genau das Problem löst, an dem konsistente
Datenmodelle typischerweise scheitern: dieselbe fachliche Regel an zehn Stellen unterschiedlich implementiert.

Der Vortrag zeigt Domains nicht als Syntax-Showcase, sondern als gezieltes Mittel zur Reinhaltung der Daten: Wie sich
fachliche Wertebereiche (E-Mail, Telefonnummer, Kennzeichen, Spannungsklassen, Enum-LoVs) einmal definieren und überall
durchsetzen lassen, was bei der Evolution bestehender Domains passiert (FORCE PRESERVE, Relinking betroffener Spalten)
und wo die Grenzen liegen. Behandelt werden außerdem die seit 23.4 verfügbaren Enum-Domains und ein erfahrungsbasierter
Blick auf überraschendes WHERE-Klausel-Verhalten bei Enum-Spalten – ein Stolperstein, der in keiner Doku steht.

Eine Live-Demo gegen eine 23ai/26ai-ADB führt vom unkontrollierten Wildwuchs zum sauberen, zentral gepflegten
Modell – inklusive Migration bestehender Tabellen und der Dictionary-Abfragen, mit denen man vor einem DROP DOMAIN
herausfindet, welche Spalten überhaupt betroffen sind.

**Keywords:** SQL Domains, Use Case Domains, Datenqualität, Datenhygiene, Single Point of Definition, Constraints,
Enum-Domains, Datenmodellierung

## Inhalt

```
Vortrag/
├── Folien.html            -- Folien als lokale Webseite; die Demo-Schritte laufen per Knopf live über ORDS
├── start.cmd              -- startet den lokalen Webserver und öffnet die Folien
└── assets/                -- Bilder der Folien
Datenbank/
├── 00_zuruecksetzen.sql   -- als SYS oder SYSTEM: löscht den Benutzer DOAG_DOMAINS samt allen Objekten
├── 01_benutzer.sql        -- als SYS oder SYSTEM: legt den Benutzer DOAG_DOMAINS an (fragt das Kennwort ab)
├── pa_demo.pck            -- alle Demo-Schritte des Vortrags und das Zurücksetzen auf den Wildwuchs
├── 02_wildwuchs.sql       -- legt das verwilderte Schema des Stadtwerks mit Daten an
└── 04_ords.sql            -- ORDS-Modul „folien“: Text eines Schritts holen, Schritt ausführen, zurücksetzen
```

## Voraussetzungen

- Oracle AI Database 26ai (lokal, z. B. 26ai Free) mit ORDS unter `http://localhost:8080/ords/`
- Python 3 für den lokalen Webserver
- Ein aktueller Browser

## Einrichten

In FREEPDB1 der Reihe nach ausführen: `00_zuruecksetzen.sql` und `01_benutzer.sql` als SYS oder SYSTEM, danach als
DOAG_DOMAINS `pa_demo.pck`, `02_wildwuchs.sql` und `04_ords.sql`.

## Vortragen

`Vortrag\start.cmd` öffnet die Folien unter `http://localhost:8765/Folien.html`. Auf jeder Demo-Folie führt
**▶ Ausführen** genau den angezeigten Schritt aus, **Enter** den nächsten noch offenen. Gewollte Fehler erscheinen rot
mit der Oracle-Meldung. Der Knopf **Wildwuchs herstellen** auf der Titelfolie setzt die Datenbank vor jedem Durchlauf
zurück.

Die Uhr unten rechts zeigt Seitenzahl, verbleibende Zeit der Seite und bis zum Ende (grün im Plan; rot bei Verzug,
überzogene Zeit läuft weiter). Sie startet mit dem ersten **Enter**.

Tasten: **←/→** blättern, **Enter** Uhr starten, danach nächster Schritt, **F** Vollbild, **T** Uhr ein- und
ausblenden, **R** Uhr anhalten und zurücksetzen.

Alle Personen, Firmen, Adressen und Nummern im Stadtwerk sind erfunden; E-Mail-Adressen stehen nur unter den
reservierten Domains `example.com`, `example.org`, `example.net` und `*.example`.
