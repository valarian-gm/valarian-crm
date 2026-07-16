<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { useAlert } from 'dashboard/composables';

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

// As colunas saem do custom attribute `stage`. Adicionar um valor em
// Configuracoes -> Atributos cria uma coluna nova, sem deploy.
const stages = computed(() => {
  const definition = contactAttributes.value('contact_attribute')?.find(
    attribute => attribute.attributeKey === 'stage'
  );
  const values = definition?.attributeValues;
  return values?.length ? values : DEFAULT_STAGES;
});

const stageLabel = stage => t(`KANBAN.STAGES.${stage.toUpperCase()}`, stage);

const formatCurrency = value => {
  if (!value && value !== 0) return '';
  return Number(value).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    maximumFractionDigits: 0,
  });
};

const columnTotal = stage =>
  (columns.value[stage] || []).reduce(
    (sum, contact) => sum + Number(contact.customAttributes?.valorContrato || 0),
    0
  );

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
  columns.value[stage] = contacts || [];
};

const fetchBoard = async () => {
  isLoading.value = true;
  try {
    await Promise.all(stages.value.map(fetchStage));
  } finally {
    isLoading.value = false;
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
  if (stage === WON_STAGE && !contact.customAttributes?.valorContrato) {
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
      <woot-button
        variant="clear"
        icon="arrow-clockwise"
        :is-loading="isLoading"
        @click="fetchBoard"
      >
        {{ t('KANBAN.REFRESH') }}
      </woot-button>
    </header>

    <div class="flex flex-1 gap-4 px-6 pb-6 overflow-x-auto">
      <section
        v-for="stage in stages"
        :key="stage"
        class="flex flex-col flex-shrink-0 w-72 rounded-xl bg-n-solid-2"
      >
        <div class="flex items-center justify-between px-4 py-3">
          <span class="text-sm font-medium text-n-slate-12">
            {{ stageLabel(stage) }}
          </span>
          <span class="text-xs tabular-nums text-n-slate-11">
            {{ (columns[stage] || []).length }}
          </span>
        </div>

        <div
          v-if="stage === WON_STAGE && columnTotal(stage) > 0"
          class="px-4 pb-2 text-xs font-medium text-n-teal-11"
        >
          {{ formatCurrency(columnTotal(stage)) }}
        </div>

        <Draggable
          :list="columns[stage]"
          :group="{ name: 'leads' }"
          item-key="id"
          tag="ul"
          role="list"
          class="flex flex-col gap-2 px-3 pb-3 overflow-y-auto min-h-24"
          @change="event => onDrop(event, stage)"
        >
          <template #item="{ element }">
            <li
              class="list-none rounded-lg bg-n-solid-1 border border-n-weak hover:border-n-slate-6"
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
                  <p
                    v-if="element.customAttributes?.valorContrato"
                    class="mt-1 text-xs font-medium text-n-teal-11"
                  >
                    {{ formatCurrency(element.customAttributes.valorContrato) }}
                  </p>
                  <span
                    v-if="element.customAttributes?.utmSource"
                    class="inline-block px-2 py-0.5 mt-2 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
                  >
                    {{ element.customAttributes.utmSource }}
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
            </li>
          </template>
        </Draggable>
      </section>
    </div>
  </div>
</template>
