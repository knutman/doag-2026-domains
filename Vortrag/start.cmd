@echo off
rem Startet einen lokalen Webserver für die Folien und öffnet sie im Browser.
rem ORDS nimmt die Knöpfe der Demo (POST) nur von http://localhost:8766 an; als Datei geöffnet, schickt der Browser
rem die Herkunft "null", und ORDS lehnt ab. Den Webserver beendet man durch Schließen seines Fensters.

cd /d "%~dp0"
start "Folien-Webserver" /min python -m http.server 8766 --bind 127.0.0.1
timeout /t 2 /nobreak >nul
start "" http://localhost:8766/Folien.html
