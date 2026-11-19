-- ============================================================================
-- DAVCaster Helper - Internationalization (EN default / PT-BR)
-- Keeps OTClient game UI strictly in English while letting Helper switch per char.
-- ============================================================================

local currentHelperLanguage = 'en'

local EN_TO_PT = {
  -- Main Window & Bottom Bar
  ['DAVCaster Helper'] = 'DAVCaster Helper',
  ['Helper Status:'] = 'Status do Helper:',
  ['Enabled'] = 'Ativado',
  ['Disabled'] = 'Desativado',
  ['On'] = 'Lig.',
  ['Off'] = 'Desl.',
  ['Set Key'] = 'Atalho',
  ['Close'] = 'Fechar',
  ['IDs Menu'] = 'Menu IDs',
  ['davhud shortcuts'] = 'Atalhos HUD',
  ['Open DAVCaster'] = 'Abrir DAVCaster',

  -- Tabs
  ['HEALING'] = 'CURA',
  ['TOOLS'] = 'EXTRAS',
  ['SHOOTER'] = 'MAGIAS',
  ['TARGET'] = 'TARGET',
  ['CAVEBOT'] = 'CAVEBOT',
  ['SETTINGS'] = 'CONFIG.',

  -- Stats MiniWindow
  ['Voc:'] = 'Voc:',
  ['Unknown'] = 'Desconhecida',
  ['Healing'] = 'Cura',
  ['Auto Target'] = 'Auto Target',
  ['DAVCaster'] = 'Shooter',
  ['Cavebot'] = 'Cavebot',

  -- Healing Tab
  ['Self Healing'] = 'Cura Pessoal',
  ['Sio / Friend'] = 'Sio / Aliado',
  ['Mas Res / Party'] = 'Mas Res / Party',
  ['Spell Healing (Unlimited Rules)'] = 'Cura por Magia (Regras Ilimitadas)',
  ['+ Add Spell'] = '+ Magia',
  ['Potion Healing (Unlimited Rules / Drop Item)'] = 'Cura por Poção (Regras / Arrastar Item)',
  ['+ Add Potion'] = '+ Poção',
  ['Empty Spell'] = 'Slot Vazio',
  ['Click slot'] = 'Clique no slot',
  ['Click icon to pick'] = 'Clique no ícone',
  ['Empty Potion'] = 'Sem Poção',
  ['Empty / Drop Potion'] = 'Vazio / Arraste Poção',
  ['Select trigger condition: HP% <= X, MP% <= X or MP% >= X'] = 'Condição: HP% <= X, MP% <= X ou MP% >= X',
  ['Click to toggle Potion Trigger (HP / MP / Spirit)'] = 'Clique para alternar o gatilho (HP / MP / Spirit)',
  ['Anti-Paralyze'] = 'Anti-Paralyze',
  ['Quick Sio'] = 'Quick Sio',
  ['Auto Utamo'] = 'Auto Utamo',
  ['Auto Recovery'] = 'Recup. Auto',
  ['Enable Healing'] = 'Ativar Cura',
  ['Enable Exura Sio (Friend)'] = 'Ativar Exura Sio (Aliado)',
  ['Enable Restore Balance (Friend)'] = 'Ativar Restore Balance (Aliado)',
  ['Self HP>=%'] = 'Seu HP>=%',
  ['Self MP>=%'] = 'Sua MP>=%',
  ['Enable Exura Gran Sio (Emergency -20% HP)'] = 'Ativar Exura Gran Sio (Emergência -20% HP)',
  ['Target Friends Filter:'] = 'Filtro de Aliados:',
  ['Party Members'] = 'Membros Party',
  ['Guild Members'] = 'Membros Guild',
  ['All Players on Screen'] = 'Todos na Tela',
  ['Extra Friend Names (comma separated):'] = 'Amigos Extras (separados por vírgula):',
  ['Enable Exura Gran Mas Res'] = 'Ativar Exura Gran Mas Res',
  ['Heal Count >='] = 'Mín. Alvos >=',
  ['Target HP% <='] = 'HP Alvo% <=',
  ['Self MP% >='] = 'Sua MP% >=',
  ['Include Party Members in Area'] = 'Incluir Membros da Party na Área',
  ['Include Guild Members in Area'] = 'Incluir Membros da Guild na Área',
  ['Include Self HP in Mas Res Count'] = 'Incluir seu próprio HP na contagem',

  -- Tools Tab
  ['Mana Training'] = 'Treino de Mana',
  ['Cast in PZ'] = 'Usar na PZ',
  ['Enable'] = 'Ativar',
  ['Auto Haste'] = 'Auto Haste',
  ['Enable Auto Haste'] = 'Ativar Auto Haste',
  ['Exercise Training (Click Icon to Select)'] = 'Treino Exercise (Clique p/ Selecionar)',
  ['Scan'] = 'Buscar',
  ['BP Weapons:'] = 'Armas BP:',
  ['Screen Dummys:'] = 'Dummys Tela:',
  ['Enable Auto Exercise Training'] = 'Ativar Treino Exercise Auto',
  ['Item Timer (Drag Item from BP)'] = 'Timer de Item (Arraste da BP)',
  ['Every (sec):'] = 'A cada (seg):',
  ['Enable Item Timer'] = 'Ativar Timer de Item',
  ['Next: Ready'] = 'Próx.: Pronto',
  ['Next: Disabled'] = 'Próx.: Desativado',
  ['Follow'] = 'Seguir (Follow)',
  ['Target Player:'] = 'Target Player:',
  ['Follow someone in-game or click Pick'] = 'Dê follow no jogo ou clique em Pegar',
  ['Clear follow target'] = 'Limpar alvo do follow',
  ['Pick'] = 'Pegar',
  ['Copy current followed or attacked creature name'] = 'Copia o nome do alvo ou criatura seguida',
  ['Mode:'] = 'Modo:',
  ['Dist:'] = 'Dist:',
  ['Turn'] = 'Virar',
  ['Enable Follow'] = 'Ativar Follow',
  ['Default'] = 'Padrão',
  ['Front'] = 'Frente',
  ['Back'] = 'Atrás',
  ['Left'] = 'Esquerda',
  ['Right'] = 'Direita',
  ['Character Utilities'] = 'Utilidades do Char',
  ['Change Gold'] = 'Change Gold',
  ['Auto Eat Food (All Server Food IDs)'] = 'Comer Food Auto (Todas as Foods)',
  ['Auto Bless (!bless only if missing blessings)'] = 'Auto Bless (!bless se faltar blessing)',
  ['Anti-AFK (Rotate Direction Every 10 min)'] = 'Anti-AFK (Girar a cada 10 min)',

  -- Shooter Tab
  ['Enable Magic Shooter'] = 'Ativar Shooter',
  ['Disable in PZ'] = 'Desativar na PZ',
  ['Select Spell / Rune'] = 'Selecionar Magia / Runa',
  ['No rule selected'] = 'Nenhuma regra selecionada',
  ['Select rule type: Spell (Attack/Challenge) or Rune'] = 'Tipo da regra: Magia (Ataque/Exeta) ou Runa',
  ['Requires Target'] = 'Exige Alvo',
  ['Monster filter: All Monsters = any creature. Target Name = only the name typed in the box.'] = 'Filtro: Todos Monstros = qualquer criatura. Nome do Alvo = só o nome digitado.',
  ['Mana%:'] = 'Mana%:',
  ['Creatures:'] = 'Criaturas:',
  ['Comparison: >= (At least), = (Exact), < (Less than)'] = 'Comparação: >= (Pelo menos), = (Exato), < (Menor que)',
  ['Delay:'] = 'Delay:',
  ['Up'] = 'Subir',
  ['Down'] = 'Descer',
  ['Delete'] = 'Excluir',
  ['New Rule'] = 'Nova Regra',
  ['Condition Settings'] = 'Condições Extra',
  ['Preset:'] = 'Preset:',
  ['New'] = 'Novo',
  ['Rename'] = 'Renomear',
  ['Duplicate'] = 'Duplicar',
  ['Del'] = 'Del',
  ['Spell'] = 'Magia',
  ['Rune'] = 'Runa',
  ['All Monsters'] = 'Todos Monstros',
  ['Target Name'] = 'Nome do Alvo',
  ['Target Name...'] = 'Nome do Alvo...',

  -- Target Tab
  ['Enable Auto Target'] = 'Ativar Auto Target',
  ['Default mode:'] = 'Modo padrão:',
  ['Max range:'] = 'Alcance:',
  ['Keep target until dead'] = 'Manter alvo até morrer',
  ['Stand = do not chase the target. Chase = walk after the target.'] = 'Parado = não segue o alvo. Seguir = anda atrás do alvo.',
  ['Stand'] = 'Parado',
  ['Chase'] = 'Seguir',
  ['Monster:'] = 'Monstro:',
  ['Switch Immediately'] = 'Trocar Imediatamente',
  ['When enabled, switches immediately to a monster matching this rule (even with Keep target until dead active). Rules at the top have higher priority.'] = 'Quando ativo, troca na hora para o monstro desta regra (mesmo mantendo o alvo). Regras no topo têm prioridade.',
  ['Dn'] = 'Bx',
  ['Ignore creatures (comma separated):'] = 'Ignorar criaturas (separadas por vírgula):',
  ['Mode A: closest target\nMode B: farthest target\nMode C: lowest health\nMode D: highest health\nMode E: best target for area runes / diamond arrow (most monsters around it)\nMode F: closest target, prioritizing lowest health\nMode G: closest target with highest health\nMode H: farthest target with lowest health\nMode I: farthest target with highest health'] =
    'Modo A: alvo mais próximo\nModo B: alvo mais distante\nModo C: menor HP\nModo D: maior HP\nModo E: melhor alvo p/ runa em área / diamond arrow (mais monstros ao redor)\nModo F: mais próximo com menor HP\nModo G: mais próximo com maior HP\nModo H: mais distante com menor HP\nModo I: mais distante com maior HP',
  ['Mode A: closest target\nMode B: farthest target\nMode C: lowest health\nMode D: highest health\nMode E: best area rune / diamond arrow cluster\nMode F: closest + lowest HP\nMode G: closest + highest HP\nMode H: farthest + lowest HP\nMode I: farthest + highest HP'] =
    'Modo A: mais próximo\nModo B: mais distante\nModo C: menor HP\nModo D: maior HP\nModo E: melhor grupo p/ área / diamond arrow\nModo F: mais próximo + menor HP\nModo G: mais próximo + maior HP\nModo H: mais distante + menor HP\nModo I: mais distante + maior HP',

  -- Cavebot Tab & Mini-HUD
  ['Enable Cavebot'] = 'Ativar Cavebot',
  ['Auto Rec'] = 'Gravar Auto',
  ['Dist (SQM):'] = 'Dist (SQM):',
  ['Distance between recorded Nodes. Rope / Ladder / Hole / Shovel are always recorded, regardless of distance.'] = 'Distância entre Nodes gravados. Corda / Escada / Buraco / Pá são sempre gravados.',
  ['Start Nearest'] = 'Iniciar +Próx.',
  ['Show CB Mini-HUD'] = 'Abrir Mini-HUD',
  ['Show Waypoints on Map'] = 'Mostrar Waypoints no Mapa',
  ['Speed (%):'] = 'Vel. (%):',
  ['Cavebot walking speed (0-100%). 100% = full character speed, 0% = stopped. Updates automatically when Dynamic Lure is active.'] = 'Velocidade do Cavebot (0-100%). 100% = normal, 0% = parado. Atualiza sozinho no Lure Dinâmico.',
  ['100% = character walks at full native speed. Lower % slows step frequency. 0% = stopped. Dynamic Lure adapts speed % by monster count.'] = '100% = anda na velocidade normal. Menor % reduz os passos. 0% = parado. O Lure Dinâmico ajusta conforme os monstros.',
  ['Settings'] = 'Ajustes',
  ['Rope'] = 'Corda',
  ['Shovel'] = 'Pá',
  ['Ladder'] = 'Escada',
  ['Hole'] = 'Buraco',
  ['Use Tile'] = 'Usar Tile',
  ['Start Lure'] = 'Iniciar Lure',
  ['End Lure'] = 'Fim Lure',
  ['Box'] = 'Box',
  ['Adds End Lure, Stand and Start Lure on the target tile.'] = 'Adiciona End Lure, Stand e Start Lure no tile alvo.',
  ['Rope Item:'] = 'Item Corda:',
  ['Shovel Item:'] = 'Item Pá:',
  ['Center'] = 'Centralizar',
  ['Undo'] = 'Desfazer',
  ['Clear All'] = 'Limpar Tudo',
  ['Hunt name:'] = 'Nome da Hunt:',
  ['Save Hunt'] = 'Salvar Hunt',
  ['Load Hunt'] = 'Carregar Hunt',
  [':: CAVEBOT CONTROL ::'] = ':: CONTROLE CAVEBOT ::',

  -- Settings Tab
  ['Current Character Profile'] = 'Perfil do Personagem Atual',
  ['Character:'] = 'Personagem:',
  ['Vocation:'] = 'Vocação:',
  ['Helper Language:'] = 'Idioma do Helper:',
  ['Save Profile Now'] = 'Salvar Perfil',
  ['Reload Saved'] = 'Recarregar Salvo',
  ['Reset to Default'] = 'Restaurar Padrão',
  ['Save Named Backup / Template'] = 'Salvar Cópia / Modelo Nomeado',
  ['Template name:'] = 'Nome da cópia:',
  ['Save Copy'] = 'Salvar Cópia',
  ['Saved Profiles (Load or Copy to Current Character)'] = 'Perfis Salvos (Carregar ou Copiar para o Char Atual)',
  ['Select a character or template below to copy its entire Helper setup (healing, shooter, target, tools, cavebot & hotkeys) to your current character.'] = 'Selecione um personagem ou modelo abaixo para copiar toda a configuração do Helper (cura, shooter, target, extras, cavebot e atalhos) para o char atual.',
  ['Refresh List'] = 'Atualizar Lista',
  ['Load / Copy to Current Char'] = 'Carregar / Copiar p/ Char Atual',
  ['Delete Selected'] = 'Excluir Selecionado',

  -- Modals
  ['Select Spell'] = 'Selecionar Magia',
  ['Cancel'] = 'Cancelar',
  ['Apply'] = 'Aplicar',
  ['Ok'] = 'Ok',
  ['Parameter'] = 'Parâmetro',
  ['Only show vocation spells'] = 'Mostrar apenas magias da vocação',
  ['Select Item'] = 'Selecionar Item',
  ['Clear'] = 'Limpar',
  ['Custom Item ID:'] = 'ID do Item:',
  ['Rename Preset'] = 'Renomear Preset',
  ['New Preset Name:'] = 'Novo Nome do Preset:',
  ['Cast If Trapped'] = 'Usar se Trapped (cercado)',
  ['Only cast this spell when surrounded/trapped'] = 'Só usar esta magia se estiver cercado',
  ['Player stopped'] = 'Char parado',
  ['for'] = 'por',
  ['Only cast if your character has stood still for at least this many ms'] = 'Só usar se o personagem ficar parado por pelo menos este tempo (ms)',
  ['Only If Target Adjacent (1 SQM)'] = 'Só com Alvo Colado (1 SQM)',
  ['Require at least one monster/target within 1 SQM melee distance'] = 'Exige pelo menos um monstro/alvo a 1 SQM (colado)',
  ['Force Spell On Most Targets'] = 'Virar p/ Maior Grupo',
  ['Auto turn toward the direction with the most targets for wave/beam spells'] = 'Vira automaticamente para a direção com mais monstros (waves/beams)',
  ['On Momentum, prioritize spell'] = 'Priorizar no Momentum',
  ['Prioritize this spell when Momentum triggers'] = 'Prioriza esta magia quando ativar Momentum',
  ['Set Shortcut Key'] = 'Definir Atalho',
  ['Press any key combination...'] = 'Pressione a combinação de teclas...',
  ['Current: None'] = 'Atual: Nenhum',
  ['Cavebot & Dynamic Lure Settings'] = 'Ajustes de Cavebot e Lure Dinâmico',
  ['Stop walking (hold & kill) when monsters >='] = 'Parar para matar quando monstros >=',
  ['Resume walking when monsters <='] = 'Voltar a andar quando monstros <=',
  ['Enable Dynamic Lure (speed adapts to monster count)'] = 'Ativar Lure Dinâmico (velocidade adapta aos monstros)',
  ['Walking speed (%) by nearby monster count. 100% = full native speed; 50% = half speed; 0% = stopped.'] = 'Velocidade (%) por quantidade de monstros por perto. 100% = normal; 50% = metade; 0% = parado.',
  ['0 mon'] = '0 mon',
  ['1 mon'] = '1 mon',
  ['2 mon'] = '2 mon',
  ['3 mon'] = '3 mon',
  ['4 mon'] = '4 mon',
  ['5+ mon'] = '5+ mon',
  ['Custom IDs Manager'] = 'Gerenciador de IDs',
  ['Follow IDs'] = 'IDs de Follow',
  ['Training Dummys'] = 'Dummys de Treino',
  ['Training Weapons'] = 'Armas de Treino',
  ['Stairs'] = 'Escadas',
  ['Use/Doors'] = 'Usar/Portas',
  ['Teleports'] = 'Teleports',
  ['Avoid'] = 'Evitar',
  ['Add ID:'] = 'Add ID:',
  ['+ Add ID'] = '+ Add ID',
  ['Remove'] = 'Remover',
  ['Saved Hunts (mods/game_helper/cavebots)'] = 'Hunts Salvas (mods/game_helper/cavebots)',
  ['Load Selected'] = 'Carregar Hunt',

  -- Dynamic Labels, Tooltips & Status Messages
  ['[DAVCaster] Helper %s'] = '[DAVCaster] Helper %s',
  ['ENABLED'] = 'ATIVADO',
  ['DISABLED'] = 'DESATIVADO',
  ['%s (%s)\nLeft-click to select | Right-click to clear'] = '%s (%s)\nBotão esq.: selecionar | Botão dir.: limpar',
  ['Empty Spell Slot\nLeft-click to select spell'] = 'Slot de Magia Vazio\nBotão esq. para escolher',
  ['%s (ID: %d)\nClick or Drop Item from BP | Right-click to clear'] = '%s (ID: %d)\nClique ou arraste da BP | Dir.: limpar',
  ['Empty Item Slot\nClick to choose OR Drop Item from BP'] = 'Slot de Item Vazio\nClique ou arraste um item da BP',
  ['None in BP'] = 'Nenhuma na BP',
  ['None on Screen'] = 'Nenhum na Tela',
  ['Weapon: %s | Dummy: %s'] = 'Arma: %s | Dummy: %s',
  ['[DAVCaster] Found %d exercise weapon(s) in BP, %d dummy(s) on screen.'] = '[DAVCaster] Encontrado(s): %d arma(s) na BP, %d dummy(s) na tela.',
  ['Next: %ds'] = 'Próx.: %ds',
  ['Status: '] = 'Status: ',
  ['Running WP #%d/%d'] = 'Rodando WP #%d/%d',
  ['Idle (%d WPs)'] = 'Parado (%d WPs)',
  [' [Luring/Paused]'] = ' [Lure/Pausado]',
  ['Mode '] = 'Modo ',
  [' | [Interrupt]'] = ' | [Trocar]',
  ['Auto Rec: '] = 'Auto Gravar: ',
  ['Ready.'] = 'Pronto.',
  ['Saved profile for "%s".'] = 'Perfil salvo para "%s".',
  ['Reloaded saved profile for "%s".'] = 'Perfil salvo recarregado para "%s".',
  ['Profile "%s" reset to defaults.'] = 'Perfil "%s" restaurado para o padrão.',
  ['Enter a template name first.'] = 'Digite um nome para a cópia primeiro.',
  ['Saved template copy "%s".'] = 'Cópia salva como "%s".',
  ['Select a saved profile from the list first.'] = 'Selecione um perfil da lista primeiro.',
  ['Loaded profile "%s" into "%s".'] = 'Perfil "%s" carregado para "%s".',
  ['Cannot delete the active character profile (use Reset to Default).'] = 'Não é possível excluir o perfil ativo (use Restaurar Padrão).',
  ['Deleted profile "%s".'] = 'Perfil "%s" excluído.',
  [' [Current]'] = ' [Atual]',
  ['%d vocs'] = '%d vocações',
  ['Ignore Trapped Monsters'] = 'Ignorar Monstros Presos',
  ['Ignores monsters trapped behind walls or unreachable tiles in Cavebot.'] = 'Ignora monstros presos atrás de paredes ou inacessíveis no Cavebot.',
  ['Sec:'] = 'Seg:',
  ['Interval in seconds between mana training casts'] = 'Intervalo em segundos entre as magias de mana training',
  ['Offline'] = 'Offline'
}

function getHelperLanguage()
  return currentHelperLanguage == 'pt' and 'pt' or 'en'
end

function setHelperLanguageState(lang)
  currentHelperLanguage = (lang == 'pt') and 'pt' or 'en'
  return currentHelperLanguage
end

function ht(enText)
  if type(enText) ~= 'string' then return enText end
  if currentHelperLanguage == 'pt' then
    return EN_TO_PT[enText] or enText
  end
  return enText
end

-- Safe translation + formatting helper: avoids % errors if there are no args
function htf(enText, ...)
  local fmt = ht(enText)
  if select('#', ...) > 0 then
    return string.format(fmt, ...)
  end
  return fmt
end

local function translateStaticWidget(widget)
  if not widget then return end
  if widget.getText and widget.setText then
    local cur = widget:getText()
    if widget._i18nKey == nil and type(cur) == 'string' and cur ~= '' and EN_TO_PT[cur] then
      widget._i18nKey = cur
    end
    if widget._i18nKey then
      local target = ht(widget._i18nKey)
      if cur ~= target then
        widget:setText(target)
      end
    end
  end
  if widget.getTooltip and widget.setTooltip then
    local tt = widget:getTooltip()
    if widget._i18nTooltipKey == nil and type(tt) == 'string' and tt ~= '' and EN_TO_PT[tt] then
      widget._i18nTooltipKey = tt
    end
    if widget._i18nTooltipKey then
      local targetTt = ht(widget._i18nTooltipKey)
      if tt ~= targetTt then
        widget:setTooltip(targetTt)
      end
    end
  end
  if widget.getChildren then
    for _, child in ipairs(widget:getChildren()) do
      translateStaticWidget(child)
    end
  end
end

function translateWidgetTree(root)
  if root then
    translateStaticWidget(root)
  end
end
