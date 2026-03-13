# DuckSearch Skill

## Propósito
Permite realizar búsquedas web utilizando DuckDuckGo directamente desde Reinike Bot.

## Comandos disponibles

### Búsqueda básica
```bash
python duck_search.py <query>
powershell duck_search.ps1 -Query "<query>"
```

Donde `<query>` es el término de búsqueda.

## Ejemplos de uso

### Python
```bash
python duck_search.py "chile noticias"
python duck_search.py "recetas de cocina"
python duck_search.py "python tutorials"
```

### PowerShell
```powershell
.\duck_search.ps1 -Query "chile noticias"
.\duck_search.ps1 -Query "recetas de cocina"
.\duck_search.ps1 -Query "python tutorials"
```

## Requisitos
- Python 3.7+
- Paquete `ddgs`: `pip install ddgs`

## Salida
El script retorna hasta 10 resultados con:
- Título del resultado
- URL
- Descripción (truncada a 200 caracteres)
