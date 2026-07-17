<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
import { useStageLabels } from 'dashboard/composables/useStageLabels';
import Button from 'dashboard/components-next/button/Button.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import StageEditor from '../components/StageEditor.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

// Fallback caso a rake valarian:setup_kanban ainda nao tenha rodado.
const DEFAULT_STAGES = ['novo', 'qualificado', 'cliente', 'nao_responde', 'excluir'];
// Estagio que exige o valor do contrato (e que dispara o evento de venda).
const WON_STAGE = 'cliente';
// Coluna de entrada: alem dos marcados explicitamente, pesca todo contato que
// ainda NAO tem estagio. E o que faz o lead novo cair no board sozinho, sem
// ninguem precisar marcar nada.
const INBOX_STAGE = 'novo';

const isLoading = ref(false);
// { [stage]: Contact[] }
const columns = ref({});

const contactAttributes = useMapGetter('attributes/getAttributesByModel');

// ATENCAO ao shape: o getter `getAttributesByModel` NAO cameliza (diferente dos
// vizinhos getContactAttributes/getCompanyAttributes, que fazem .map(camelcaseKeys)).
// Aqui os campos chegam em snake_case: attribute_key, attribute_values.
const stageDefinition = computed(() =>
  contactAttributes
    .value('contact_attribute')
    ?.find(attribute => attribute.attribute_key === 'stage')
);

const stages = computed(() => {
  const values = stageDefinition.value?.attribute_values;
  return values?.length ? values : DEFAULT_STAGES;
});

// Rotulo customizado > traducao padrao > chave humanizada.
const { stageLabel, customLabels } = useStageLabels();

// Etapas que o editor nao deixa remover: sem elas o board perde as regras
// (a de entrada pesca quem nao tem estagio; a de venda pede o valor).
const LOCKED_STAGES = [INBOX_STAGE, WON_STAGE];

const isEditorOpen = ref(false);
const isSavingStages = ref(false);

const limparDatas = () => {
  dateFrom.value = '';
  dateTo.value = '';
  fetchBoard();
};

const stageCounts = computed(() =>
  stages.value.reduce((acc, stage) => {
    acc[stage] = (columns.value[stage] || []).length;
    return acc;
  }, {})
);

const saveStages = async ({ stages: novosEstagios, labels }) => {
  if (!stageDefinition.value?.id) {
    useAlert(t('KANBAN.EDITOR.NO_DEFINITION'));
    return;
  }
  isSavingStages.value = true;
  try {
    // As CHAVES vivem no custom attribute (é o que o contato guarda)...
    await store.dispatch('attributes/update', {
      id: stageDefinition.value.id,
      attribute_values: novosEstagios,
    });
    // ...e os ROTULOS na conta. Separados de proposito: renomear nao pode
    // orfanar lead nem quebrar o codigo que depende de 'novo'/'cliente'.
    await store.dispatch('accounts/update', {
      kanban_stage_labels: labels,
    });
    isEditorOpen.value = false;
    await fetchBoard();
    useAlert(t('KANBAN.EDITOR.SAVED'));
  } catch (error) {
    useAlert(error.message || t('KANBAN.EDITOR.SAVE_ERROR'));
  } finally {
    isSavingStages.value = false;
  }
};

const formatCurrency = value => {
  if (!value && value !== 0) return '';
  return Number(value).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
};

// Soma o que esta visivel: lead perdido nao infla o numero.
const columnTotal = stage =>
  cardsDe(stage).reduce((sum, contact) => sum + valorDe(contact), 0);

// Total do topo = so a coluna Cliente. Somar todas as colunas misturaria o que
// nao deve (lead em 'excluir' com valor entraria na conta); o numero que importa
// e o contrato FECHADO.
const wonTotal = computed(() => columnTotal(WON_STAGE));
const wonCount = computed(() => (columns.value[WON_STAGE] || []).length);

// Abrir o lead = abrir a CONVERSA (e onde se trabalha: le o papo e responde).
// O contato fica como acao secundaria (icone no card).
const conversationsOf = useMapGetter(
  'contactConversations/getAllConversationsByContactId'
);

const openConversation = async contact => {
  let conversations = conversationsOf.value(contact.id);
  if (!conversations?.length) {
    await store.dispatch('contactConversations/get', contact.id);
    conversations = conversationsOf.value(contact.id);
  }
  const conversationId = conversations?.[0]?.id;
  if (!conversationId) {
    useAlert(t('KANBAN.NO_CONVERSATION'));
    return;
  }
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
};

const openContact = contact => {
  router.push({ name: 'contacts_edit', params: { contactId: contact.id } });
};

// `contacts/filter` devolve o payload CRU da API (snake_case), sem passar pelo
// getter que cameliza. Normaliza num lugar so.
// Nota: as chaves DENTRO de custom_attributes ficam snake_case de proposito —
// ate o getter oficial usa stopPaths: ['custom_attributes'] (sao chaves criadas
// pelo usuario, nao devem ser transformadas).
const normalize = contact => ({
  id: contact.id,
  name: contact.name,
  email: contact.email,
  phoneNumber: contact.phone_number,
  thumbnail: contact.thumbnail,
  createdAt: contact.created_at,
  lastActivityAt: contact.last_activity_at,
  customAttributes: contact.custom_attributes || {},
});

// "há quanto tempo parado" — o dado que faltava no card. Lead esquecido no
// funil e o que mais custa dinheiro.
const tempoParado = contact => {
  const stamp = contact.lastActivityAt || contact.createdAt;
  if (!stamp) return '';
  const segundos = Number(stamp) > 1e12 ? Number(stamp) / 1000 : Number(stamp);
  const dias = Math.floor((Date.now() / 1000 - segundos) / 86400);
  if (Number.isNaN(dias) || dias < 0) return '';
  if (dias === 0) return t('KANBAN.TODAY');
  return t('KANBAN.DAYS_AGO', { count: dias });
};

// Alerta visual: lead parado ha muito tempo.
const estaFrio = contact => {
  const stamp = contact.lastActivityAt || contact.createdAt;
  if (!stamp) return false;
  const segundos = Number(stamp) > 1e12 ? Number(stamp) / 1000 : Number(stamp);
  return (Date.now() / 1000 - segundos) / 86400 > 7;
};

const valorDe = contact => Number(contact.customAttributes?.valor_contrato || 0);
const utmDe = contact => contact.customAttributes?.utm_source;
const arquivadoDe = contact => Boolean(contact.customAttributes?.arquivado);

// Lead perdido some da visao padrao. Filtro no cliente: o board ja tem os
// contatos em memoria, nao vale complicar a query (e o OR da coluna de entrada)
// pra economizar um filtro de array.
const showArchived = ref(false);

const cardsDe = stage => {
  const todos = columns.value[stage] || [];
  return showArchived.value ? todos : todos.filter(c => !arquivadoDe(c));
};

const archivedCount = computed(() =>
  stages.value.reduce(
    (total, stage) =>
      total + (columns.value[stage] || []).filter(arquivadoDe).length,
    0
  )
);

// Filtro por data de ENTRADA do lead (created_at) — a data que casa com
// campanha/UTM e alimenta o CAC.
const dateFrom = ref('');
const dateTo = ref('');
const hasDateFilter = computed(() => Boolean(dateFrom.value || dateTo.value));

const dateConditions = () => {
  const conditions = [];
  if (dateFrom.value) {
    conditions.push({
      attribute_key: 'created_at',
      filter_operator: 'is_greater_than',
      values: [dateFrom.value],
    });
  }
  if (dateTo.value) {
    conditions.push({
      attribute_key: 'created_at',
      filter_operator: 'is_less_than',
      values: [dateTo.value],
    });
  }
  return conditions;
};

// O FilterService concatena as condicoes SEM parenteses
// (query_builder: @query_string += " #{...}"). Como AND tem precedencia sobre
// OR, `A OR B AND C` vira `A OR (B AND C)` — por isso NUNCA misturamos OR com
// o filtro de data no mesmo payload (ver fetchStage).
const buildPayload = conditions =>
  conditions.map((condition, index) => ({
    ...condition,
    query_operator: index === conditions.length - 1 ? null : 'AND',
  }));

const runFilter = async conditions => {
  const contacts = await store.dispatch('contacts/filter', {
    queryPayload: { payload: buildPayload(conditions) },
    // resetState: false — nao limpa a lista global entre colunas.
    resetState: false,
  });
  return (contacts || []).map(normalize);
};

const stageIs = stage => ({
  attribute_key: 'stage',
  filter_operator: 'equal_to',
  values: [stage],
});
const stageAusente = {
  attribute_key: 'stage',
  filter_operator: 'is_not_present',
  values: [],
};

const fetchStage = async stage => {
  const datas = dateConditions();

  if (stage !== INBOX_STAGE) {
    columns.value[stage] = await runFilter([stageIs(stage), ...datas]);
    return;
  }

  // Coluna de entrada = "sem estagio" OU "marcado como novo". Como nao da pra
  // usar OR junto do AND da data (precedencia), sao DUAS queries + merge.
  const [semEstagio, marcados] = await Promise.all([
    runFilter([stageAusente, ...datas]),
    runFilter([stageIs(stage), ...datas]),
  ]);
  const porId = new Map();
  [...semEstagio, ...marcados].forEach(contact => porId.set(contact.id, contact));
  columns.value[stage] = [...porId.values()];
};

const fetchBoard = async () => {
  isLoading.value = true;
  try {
    await Promise.all(stages.value.map(fetchStage));
  } finally {
    isLoading.value = false;
  }
};

// Acoes rapidas do card: o trabalho do dia a dia sem drag nem sair do board.
const marcarGanho = async contact => {
  let valor = valorDe(contact);
  if (!valor) {
    const input = window.prompt(t('KANBAN.CONTRACT_VALUE_PROMPT'));
    if (input === null) return;
    valor = Number(String(input).replace(',', '.')) || 0;
  }
  await patchContact(contact, { stage: WON_STAGE, valor_contrato: valor });
  useAlert(t('KANBAN.WON_DONE', { name: contact.name }));
};

const marcarPerdido = async contact => {
  await patchContact(contact, { arquivado: true });
  useAlert(t('KANBAN.LOST_DONE', { name: contact.name }));
};

const restaurar = async contact => {
  await patchContact(contact, { arquivado: false });
  useAlert(t('KANBAN.RESTORED', { name: contact.name }));
};

// Edicao do valor direto no card.
const editandoValor = ref(null);
const rascunhoValor = ref('');

const abrirEdicaoValor = contact => {
  editandoValor.value = contact.id;
  rascunhoValor.value = valorDe(contact) || '';
};

const salvarValor = async contact => {
  const valor = Number(String(rascunhoValor.value).replace(',', '.')) || 0;
  editandoValor.value = null;
  if (valor === valorDe(contact)) return;
  await patchContact(contact, { valor_contrato: valor });
};

// Escreve so o que mudou: o backend faz merge raso, o resto sobrevive.
const patchContact = async (contact, customAttributes) => {
  try {
    await store.dispatch('contacts/update', { id: contact.id, customAttributes });
    await fetchBoard();
  } catch (error) {
    useAlert(t('KANBAN.MOVE_ERROR'));
    await fetchBoard();
  }
};

const persistStage = async (contact, stage, valorContrato) => {
  // O backend faz merge raso em custom_attributes: mandar so o que mudou
  // preserva utm_source, valor_contrato e o resto.
  await store.dispatch('contacts/update', {
    id: contact.id,
    customAttributes: {
      stage,
      ...(valorContrato !== undefined && { valor_contrato: valorContrato }),
    },
  });
};

const onDrop = async (event, stage) => {
  const contact = event.added?.element;
  if (!contact) return;

  let valorContrato;
  if (stage === WON_STAGE && !valorDe(contact)) {
    const input = window.prompt(t('KANBAN.CONTRACT_VALUE_PROMPT'));
    if (input === null) {
      await fetchBoard(); // cancelou: desfaz o movimento visual
      return;
    }
    valorContrato = Number(String(input).replace(',', '.')) || 0;
  }

  try {
    await persistStage(contact, stage, valorContrato);
    useAlert(t('KANBAN.MOVED', { name: contact.name, stage: stageLabel(stage) }));
    await fetchBoard();
  } catch (error) {
    useAlert(t('KANBAN.MOVE_ERROR'));
    await fetchBoard();
  }
};

onMounted(async () => {
  await store.dispatch('attributes/get');
  await fetchBoard();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header class="sticky top-0 z-10 px-6 bg-n-background">
      <div class="flex items-center justify-between w-full gap-2 py-6">
        <div class="flex items-baseline gap-3 min-w-0">
          <span class="text-xl font-medium truncate text-n-slate-12">
            {{ t('KANBAN.HEADER') }}
          </span>
          <!-- So o contrato FECHADO: somar todas as colunas misturaria lead
               descartado com venda real. -->
          <span
            v-if="wonTotal > 0"
            class="text-sm font-medium tabular-nums text-n-teal-11 shrink-0"
          >
            {{ formatCurrency(wonTotal) }}
            <span class="font-normal text-n-slate-11">
              · {{ t('KANBAN.WON_SUMMARY', { count: wonCount }) }}
            </span>
          </span>
        </div>

        <div class="flex items-center flex-shrink-0 gap-2">
          <div class="flex items-center gap-1">
            <input
              v-model="dateFrom"
              type="date"
              class="!mb-0 !h-8 !text-xs !w-32"
              :title="t('KANBAN.DATE_FROM')"
              @change="fetchBoard"
            />
            <span class="text-xs text-n-slate-10">–</span>
            <input
              v-model="dateTo"
              type="date"
              class="!mb-0 !h-8 !text-xs !w-32"
              :title="t('KANBAN.DATE_TO')"
              @change="fetchBoard"
            />
            <Button
              v-if="hasDateFilter"
              variant="ghost"
              color="slate"
              size="sm"
              icon="i-lucide-x"
              :title="t('KANBAN.DATE_CLEAR')"
              @click="limparDatas"
            />
          </div>
          <Button
            :variant="showArchived ? 'faded' : 'ghost'"
            color="slate"
            size="sm"
            :icon="showArchived ? 'i-lucide-eye' : 'i-lucide-eye-off'"
            :label="String(archivedCount)"
            :title="t('KANBAN.SHOW_ARCHIVED', { count: archivedCount })"
            @click="showArchived = !showArchived"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-settings-2"
            :title="t('KANBAN.EDITOR.OPEN')"
            @click="isEditorOpen = true"
          />
          <Button
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-refresh-cw"
            :is-loading="isLoading"
            :title="t('KANBAN.REFRESH')"
            @click="fetchBoard"
          />
        </div>
      </div>
    </header>

    <StageEditor
      v-if="isEditorOpen"
      :stages="stages"
      :counts="stageCounts"
      :locked-stages="LOCKED_STAGES"
      :labels="customLabels"
      :is-saving="isSavingStages"
      @save="saveStages"
      @close="isEditorOpen = false"
    />

    <div class="flex flex-1 gap-4 px-6 pb-6 overflow-x-auto">
      <section
        v-for="stage in stages"
        :key="stage"
        class="flex flex-col flex-shrink-0 w-72 rounded-xl bg-n-solid-2"
      >
        <div class="px-4 py-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium capitalize text-n-slate-12">
              {{ stageLabel(stage) }}
            </span>
            <span class="text-xs tabular-nums text-n-slate-11">
              {{ cardsDe(stage).length }}
            </span>
          </div>
          <!-- Soma da propria etapa: cada coluna mostra quanto tem nela. -->
          <div
            v-if="columnTotal(stage) > 0"
            class="mt-0.5 text-xs font-medium tabular-nums"
            :class="stage === WON_STAGE ? 'text-n-teal-11' : 'text-n-slate-11'"
          >
            {{ formatCurrency(columnTotal(stage)) }}
          </div>
        </div>

        <Draggable
          :list="cardsDe(stage)"
          :group="{ name: 'leads' }"
          item-key="id"
          tag="ul"
          role="list"
          class="flex flex-col gap-2 px-3 pb-3 overflow-y-auto min-h-24"
          @change="event => onDrop(event, stage)"
        >
          <template #item="{ element }">
            <li
              class="relative list-none transition-all border rounded-lg group cursor-grab bg-n-solid-1 border-n-weak hover:border-n-slate-6 hover:shadow-sm"
              :class="{ 'opacity-40 grayscale': arquivadoDe(element) }"
            >
              <!-- Corpo: clique abre a CONVERSA (onde se le o papo e responde) -->
              <button
                class="w-full p-3 text-left"
                :title="t('KANBAN.OPEN_CONVERSATION')"
                @click="openConversation(element)"
              >
                <!-- Linha 1: quem e (avatar + nome) -->
                <div class="flex items-center gap-2">
                  <Avatar
                    :name="element.name"
                    :src="element.thumbnail"
                    :size="24"
                    rounded-full
                  />
                  <span class="flex-1 text-sm font-medium truncate text-n-slate-12">
                    {{ element.name }}
                  </span>
                </div>

                <!-- Linha 2: como falar (um so — telefone manda) -->
                <p class="mt-1.5 text-xs truncate text-n-slate-11">
                  {{ element.phoneNumber || element.email }}
                </p>

                <!-- Linha 3: sinais — de onde veio e ha quanto tempo esta parado -->
                <div class="flex items-center gap-1.5 mt-2 text-xs">
                  <span
                    v-if="utmDe(element)"
                    class="px-1.5 py-0.5 rounded truncate max-w-24 bg-n-alpha-2 text-n-slate-11"
                    :title="utmDe(element)"
                  >
                    {{ utmDe(element) }}
                  </span>
                  <span
                    v-if="tempoParado(element)"
                    class="ms-auto shrink-0"
                    :class="estaFrio(element) ? 'text-n-amber-11' : 'text-n-slate-10'"
                    :title="t('KANBAN.IDLE_HINT')"
                  >
                    {{ tempoParado(element) }}
                  </span>
                </div>
              </button>

              <!-- Valor: so aparece se existe, ou no hover pra adicionar -->
              <div class="px-3 pb-2 -mt-1">
                <input
                  v-if="editandoValor === element.id"
                  v-model="rascunhoValor"
                  type="number"
                  inputmode="decimal"
                  class="w-full !h-7 !mb-0 !text-xs"
                  :placeholder="t('KANBAN.VALUE_PLACEHOLDER')"
                  autofocus
                  @click.stop
                  @blur="salvarValor(element)"
                  @keyup.enter="salvarValor(element)"
                  @keyup.esc="editandoValor = null"
                />
                <button
                  v-else-if="valorDe(element) > 0"
                  class="text-sm font-semibold tabular-nums text-n-teal-11 hover:underline"
                  :title="t('KANBAN.EDIT_VALUE')"
                  @click.stop="abrirEdicaoValor(element)"
                >
                  {{ formatCurrency(valorDe(element)) }}
                </button>
                <button
                  v-else
                  class="text-xs transition-opacity opacity-0 text-n-slate-10 group-hover:opacity-100 hover:underline"
                  @click.stop="abrirEdicaoValor(element)"
                >
                  {{ t('KANBAN.ADD_VALUE') }}
                </button>
              </div>

              <!-- Acoes: so no hover, pra o card respirar -->
              <div
                class="absolute flex items-center gap-0.5 transition-opacity opacity-0 top-2 end-2 group-hover:opacity-100 focus-within:opacity-100"
              >
                <template v-if="arquivadoDe(element)">
                  <button
                    class="p-1 rounded shrink-0 bg-n-solid-2 text-n-slate-11 hover:text-n-slate-12"
                    :title="t('KANBAN.RESTORE')"
                    @click.stop="restaurar(element)"
                  >
                    <span class="i-lucide-undo-2 size-3.5" />
                  </button>
                </template>
                <template v-else>
                  <button
                    v-if="stage !== WON_STAGE"
                    class="p-1 rounded shrink-0 bg-n-solid-2 text-n-slate-10 hover:text-n-teal-11"
                    :title="t('KANBAN.WON_HINT')"
                    @click.stop="marcarGanho(element)"
                  >
                    <span class="i-lucide-circle-check size-3.5" />
                  </button>
                  <button
                    class="p-1 rounded shrink-0 bg-n-solid-2 text-n-slate-10 hover:text-n-ruby-10"
                    :title="t('KANBAN.LOST_HINT')"
                    @click.stop="marcarPerdido(element)"
                  >
                    <span class="i-lucide-circle-x size-3.5" />
                  </button>
                  <button
                    class="p-1 rounded shrink-0 bg-n-solid-2 text-n-slate-10 hover:text-n-slate-12"
                    :title="t('KANBAN.OPEN_CONTACT')"
                    @click.stop="openContact(element)"
                  >
                    <span class="i-lucide-contact size-3.5" />
                  </button>
                </template>
              </div>
            </li>
          </template>
        </Draggable>
      </section>
    </div>
  </div>
</template>
