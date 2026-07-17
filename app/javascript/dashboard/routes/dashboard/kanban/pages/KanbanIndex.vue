<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';
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

// Etapa custom (criada pelo usuario) nao tem chave de i18n: humaniza a chave
// em vez de mostrar 'em_negociacao' cru.
const stageLabel = stage =>
  t(`KANBAN.STAGES.${stage.toUpperCase()}`, stage.replace(/_/g, ' '));

// Etapas que o editor nao deixa remover: sem elas o board perde as regras
// (a de entrada pesca quem nao tem estagio; a de venda pede o valor).
const LOCKED_STAGES = [INBOX_STAGE, WON_STAGE];

const isEditorOpen = ref(false);
const isSavingStages = ref(false);

const stageCounts = computed(() =>
  stages.value.reduce((acc, stage) => {
    acc[stage] = (columns.value[stage] || []).length;
    return acc;
  }, {})
);

const saveStages = async novosEstagios => {
  if (!stageDefinition.value?.id) {
    useAlert(t('KANBAN.EDITOR.NO_DEFINITION'));
    return;
  }
  isSavingStages.value = true;
  try {
    await store.dispatch('attributes/update', {
      id: stageDefinition.value.id,
      attribute_values: novosEstagios,
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
  customAttributes: contact.custom_attributes || {},
});

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

const stageQuery = stage => {
  const marcados = {
    attribute_key: 'stage',
    filter_operator: 'equal_to',
    values: [stage],
    query_operator: null,
  };
  if (stage !== INBOX_STAGE) return [marcados];

  // Coluna de entrada: "sem estagio" OR "marcado como novo".
  // is_not_present vira `IS NULL` no SQL (FilterService#filter_operation).
  return [
    {
      attribute_key: 'stage',
      filter_operator: 'is_not_present',
      values: [],
      query_operator: 'OR',
    },
    marcados,
  ];
};

const fetchStage = async stage => {
  const queryPayload = { payload: stageQuery(stage) };
  // resetState: false — nao limpa a lista global entre colunas.
  const contacts = await store.dispatch('contacts/filter', {
    queryPayload,
    resetState: false,
  });
  columns.value[stage] = (contacts || []).map(normalize);
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
    <header class="flex items-center justify-between px-6 py-4">
      <div class="flex items-baseline gap-4">
        <h1 class="text-xl font-medium text-n-slate-12">
          {{ t('KANBAN.HEADER') }}
        </h1>
        <!-- So o contrato FECHADO. Somar todas as colunas misturaria lead
             descartado com venda real. -->
        <div class="flex items-baseline gap-2">
          <span class="text-xl font-semibold tabular-nums text-n-teal-11">
            {{ formatCurrency(wonTotal) }}
          </span>
          <span class="text-xs text-n-slate-11">
            {{ t('KANBAN.WON_SUMMARY', { count: wonCount }) }}
          </span>
        </div>
      </div>
      <div class="flex items-center gap-1">
        <woot-button
          :variant="showArchived ? 'smooth' : 'clear'"
          @click="showArchived = !showArchived"
        >
          <span class="flex items-center gap-1.5">
            <span
              :class="showArchived ? 'i-lucide-eye' : 'i-lucide-eye-off'"
              class="size-4"
            />
            {{ t('KANBAN.SHOW_ARCHIVED', { count: archivedCount }) }}
          </span>
        </woot-button>
        <woot-button variant="clear" @click="isEditorOpen = true">
          <span class="flex items-center gap-1.5">
            <span class="i-lucide-settings-2 size-4" />
            {{ t('KANBAN.EDITOR.OPEN') }}
          </span>
        </woot-button>
        <woot-button
          variant="clear"
          icon="arrow-clockwise"
          :is-loading="isLoading"
          @click="fetchBoard"
        >
          {{ t('KANBAN.REFRESH') }}
        </woot-button>
      </div>
    </header>

    <StageEditor
      v-if="isEditorOpen"
      :stages="stages"
      :counts="stageCounts"
      :locked-stages="LOCKED_STAGES"
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
              class="list-none transition-opacity border rounded-lg bg-n-solid-1 border-n-weak hover:border-n-slate-6"
              :class="{ 'opacity-40 grayscale': arquivadoDe(element) }"
            >
              <div class="flex items-start justify-between gap-1 p-3 cursor-grab">
                <!-- Clique no corpo abre a CONVERSA: e onde se le o papo e responde. -->
                <button
                  class="flex-1 min-w-0 text-left"
                  :title="t('KANBAN.OPEN_CONVERSATION')"
                  @click="openConversation(element)"
                >
                  <p class="text-sm font-medium truncate text-n-slate-12">
                    {{ element.name }}
                  </p>
                  <p
                    v-if="element.phoneNumber"
                    class="text-xs truncate text-n-slate-11"
                  >
                    {{ element.phoneNumber }}
                  </p>
                  <p v-if="element.email" class="text-xs truncate text-n-slate-11">
                    {{ element.email }}
                  </p>
                  <span
                    v-if="utmDe(element)"
                    class="inline-block px-2 py-0.5 mt-2 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                  >
                    {{ utmDe(element) }}
                  </span>
                </button>
                <!-- Acao secundaria: ficha do contato (onde se edita o Estagio). -->
                <button
                  class="flex items-center p-1 rounded-md shrink-0 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
                  :title="t('KANBAN.OPEN_CONTACT')"
                  @click.stop="openContact(element)"
                >
                  <span class="i-lucide-contact size-4" />
                </button>
              </div>

              <!-- Valor editavel no proprio card -->
              <div class="px-3 pb-2">
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
                  v-else
                  class="text-xs font-medium tabular-nums hover:underline"
                  :class="valorDe(element) > 0 ? 'text-n-teal-11' : 'text-n-slate-10'"
                  :title="t('KANBAN.EDIT_VALUE')"
                  @click.stop="abrirEdicaoValor(element)"
                >
                  {{
                    valorDe(element) > 0
                      ? formatCurrency(valorDe(element))
                      : t('KANBAN.ADD_VALUE')
                  }}
                </button>
              </div>

              <!-- Acoes rapidas -->
              <div
                class="flex items-center gap-1 px-3 py-2 border-t border-n-weak"
              >
                <template v-if="arquivadoDe(element)">
                  <button
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-11 hover:bg-n-alpha-2"
                    @click.stop="restaurar(element)"
                  >
                    <span class="i-lucide-undo-2 size-3" />
                    {{ t('KANBAN.RESTORE') }}
                  </button>
                </template>
                <template v-else>
                  <button
                    v-if="stage !== WON_STAGE"
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-teal-11 hover:bg-n-teal-3"
                    :title="t('KANBAN.WON_HINT')"
                    @click.stop="marcarGanho(element)"
                  >
                    <span class="i-lucide-circle-check size-3" />
                    {{ t('KANBAN.WON') }}
                  </button>
                  <button
                    class="flex items-center gap-1 px-2 py-1 text-xs rounded-md text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-ruby-10"
                    :title="t('KANBAN.LOST_HINT')"
                    @click.stop="marcarPerdido(element)"
                  >
                    <span class="i-lucide-circle-x size-3" />
                    {{ t('KANBAN.LOST') }}
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
