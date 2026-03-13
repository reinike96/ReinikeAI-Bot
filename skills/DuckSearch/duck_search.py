#!/usr/bin/env python3
"""DuckSearch skill for Reinike Bot."""

import sys
from ddgs import DDGS


def main():
    if len(sys.argv) < 2:
        print("Error: Se requiere un query de búsqueda", file=sys.stderr)
        sys.exit(1)
    
    query = " ".join(sys.argv[1:])
    
    try:
        ddgs = DDGS()
        results = ddgs.text(query, max_results=10)
        
        if not results:
            print("No se encontraron resultados.")
            return
        
        for i, result in enumerate(results, 1):
            title = result['title']
            href = result['href']
            body = result.get('body', '')
            
            # Highlight prices (CLP, $, etc.) to help the AI find them
            import re
            price_match = re.search(r'(\$\s?[\d\.]+[\s\w]*|[\d\.]+\s?CLP)', body, re.IGNORECASE)
            price_info = f" [PRECIO DETECTADO: {price_match.group(0)}]" if price_match else ""
            
            print(f"{i}. {title}{price_info}")
            print(f"   {href}")
            print(f"   {body[:300]}..." if len(body) > 300 else f"   {body}")
            print()
            
    except Exception as e:
        print(f"Error en la búsqueda: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
