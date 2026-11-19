---
trigger: always_on
---

# Regras do Projeto OTClient (DavOT)

## Estilo de Resposta (Obrigatório)
- Seja extremamente direto, curto e objetivo. Zero textos longos, introduções ou explicações desnecessárias.
- Liste apenas o que foi alterado e em qual arquivo.
- Quando reportar um bug, verifique primeiro o arquivo `davot.log` na raiz.

## Arquitetura de Pastas
- **Raiz:** `init.lua`, `config.ini`, `otclient.exe`, `davot.log`.
- **Mods Customizados (`mods/`):**
  - `mods/game_helper/`: Lógica em `helper.lua`, traduções em `i18n.lua`, manifesto em `helper.otmod`. Interfaces `.otui` (`cavebot.otui`, `caster.otui`, `healing.otui`, `shooter.otui`, `target.otui`, `equipment.otui`, `modals.otui`, `settings.otui`, `stats.otui`, `tools.otui`).
  - Outros mods: `mods/game_tasks/`, `mods/game_itemselector/`, `mods/game_buttons/`, `mods/client_mods/`, `mods/client_profiles/`, `mods/client_textedit/`.
- **Módulos Base (`modules/`):** `corelib/`, `gamelib/`, `modulelib/`, `game_interface/`, `game_prey/`, `game_containers/`, `game_mainpanel/`, etc.
- **Assets (`data/`):** `styles/`, `images/`, `sounds/`, `fonts/`, `json/`, `locales/`.
- **Cliente Final (Deploy):** `C:\Users\david\AppData\Local\Programs\DavOT\client`

## Regras de Código
1. Vá direto nos caminhos listados acima antes de fazer buscas globais.
2. Use estritamente sintaxe compatível com Lua 5.1 / LuaJIT do OTClient.
3. Valide a sintaxe Lua com `luacheck.py` nos arquivos alterados antes de concluir.
