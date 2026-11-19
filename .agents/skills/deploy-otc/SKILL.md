---
name: deploy-otc
description: >-
  Valida a sintaxe Lua (luacheck.py) e faz deploy apenas dos arquivos modificados recentemente do OTClient para C:\Users\david\AppData\Local\Programs\DavOT\client. Use quando o usuário digitar /deploy-otc ou pedir para validar e publicar alterações no cliente final.
---

# Deploy OTClient (deploy-otc)

Execute os seguintes passos de forma direta:

1. **Identificar arquivos modificados:** Identifique os arquivos modificados recentemente no projeto (via `git status` ou data de modificação recente em `data/`, `mods/`, `modules/` ou raiz).
2. **Validar sintaxe Lua:** Rode `python luacheck.py` em todos os arquivos `.lua` alterados para validar a sintaxe. Se houver qualquer erro de sintaxe, interrompa o deploy e reporte o erro.
3. **Copiar para o cliente final:** Copie apenas os arquivos alterados (mantendo exatamente a mesma estrutura de pastas `data/`, `mods/`, `modules/` ou raiz) para `C:\Users\david\AppData\Local\Programs\DavOT\client`.
4. **Resposta final:** Responda apenas com a lista dos arquivos validados e copiados.
