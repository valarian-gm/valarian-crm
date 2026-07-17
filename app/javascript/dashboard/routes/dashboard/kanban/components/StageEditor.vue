<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

const props = defineProps({
  // attribute_values do custom attribute `stage`, na ordem atual do board.
  stages: { type: Array, required: true },
  // { [stage]: quantidade } — usado pra impedir remocao que sumiria com lead.
  counts: { type: Object, default: () => ({}) },
  // Etapas estruturais: nao podem ser REMOVIDAS (o board perde as regras).
  // Renomear e livre — o rotulo e so apresentacao, a chave nunca muda.
  lockedStages: { type: Array, default: () => [] },
  // { [stage]: 'Rotulo' } — rotulos customizados ja salvos na conta.
  labels: { type: Object, default: () => ({}) },
  isSaving: { type: Boolean, default: false },
});
const emit = defineEmits(['save', 'close']);
const { t } = useI18n();

// draft = a ordem/lista das CHAVES. rotulos = o texto de cada uma.
const draft = ref([...props.stages]);
const rotulos = ref({ ...props.labels });
const novoNome = ref('');
const editando = ref(null);

watch(
  () => props.stages,
  valores => {
    draft.value = [...valores];
  }
);
watch(
  () => props.labels,
  valores => {
    rotulos.value = { ...valores };
  }
);

// Mesma normalizacao do backend: o filtro faz downcase e o SQL aplica LOWER().
// Espaco vira _ pra chave nao ter caractere que atrapalhe.
const toKey = texto =>
  texto
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');

// Mesma precedencia do board: rotulo customizado > traducao > chave humanizada.
const humanize = stage =>
  rotulos.value[stage] ||
  t(`KANBAN.STAGES.${stage.toUpperCase()}`, stage.replace(/_/g, ' '));

const abrirEdicao = stage => {
  editando.value = stage;
  // Mostra o texto atual pra editar, nao vazio.
  rotulos.value[stage] = humanize(stage);
};

const salvarRotulo = stage => {
  editando.value = null;
  const texto = (rotulos.value[stage] || '').trim();
  if (!texto) {
    // Vazio = volta pro padrao (remove o customizado).
    delete rotulos.value[stage];
    return;
  }
  rotulos.value[stage] = texto;
};

const podeRemover = stage => {
  if (props.lockedStages.includes(stage)) return false;
  return !(props.counts[stage] > 0);
};

const motivoBloqueio = stage => {
  if (props.lockedStages.includes(stage)) return t('KANBAN.EDITOR.LOCKED');
  if (props.counts[stage] > 0)
    return t('KANBAN.EDITOR.HAS_LEADS', { count: props.counts[stage] });
  return '';
};

const erro = ref('');

const adicionar = () => {
  const key = toKey(novoNome.value);
  erro.value = '';
  if (!key) return;
  if (draft.value.includes(key)) {
    erro.value = t('KANBAN.EDITOR.DUPLICATE');
    return;
  }
  draft.value.push(key);
  // Guarda o texto como o usuario digitou (com acento e maiuscula); a chave
  // normalizada fica so no banco.
  rotulos.value[key] = novoNome.value.trim();
  novoNome.value = '';
};

const remover = stage => {
  if (!podeRemover(stage)) return;
  draft.value = draft.value.filter(s => s !== stage);
};

const mudou = computed(
  () =>
    JSON.stringify(draft.value) !== JSON.stringify(props.stages) ||
    JSON.stringify(rotulos.value) !== JSON.stringify(props.labels)
);

// Descarta rotulo de etapa que foi removida — nao deixa lixo na conta.
const salvar = () => {
  const limpos = {};
  draft.value.forEach(stage => {
    if (rotulos.value[stage]) limpos[stage] = rotulos.value[stage];
  });
  emit('save', { stages: draft.value, labels: limpos });
};
</script>

<template>
  <woot-modal :show="true" :on-close="() => emit('close')">
    <div class="flex flex-col w-full p-8 overflow-auto">
      <woot-modal-header
        :header-title="t('KANBAN.EDITOR.TITLE')"
        :header-content="t('KANBAN.EDITOR.SUBTITLE')"
      />

      <Draggable
        v-model="draft"
        item-key="_self"
        tag="ul"
        handle=".arrasta"
        class="flex flex-col gap-2 mt-6"
      >
        <template #item="{ element }">
          <li
            class="flex items-center gap-3 px-3 py-2 list-none border rounded-lg border-n-weak bg-n-solid-1"
          >
            <span class="cursor-grab arrasta i-lucide-grip-vertical size-4 text-n-slate-10" />
            <!-- Nome editavel: muda so o rotulo. A chave (que os leads guardam
                 e o codigo usa) fica intacta. -->
            <input
              v-if="editando === element"
              v-model="rotulos[element]"
              type="text"
              class="flex-1 !mb-0 !h-7 !text-sm"
              autofocus
              @blur="salvarRotulo(element)"
              @keyup.enter="salvarRotulo(element)"
              @keyup.esc="editando = null"
            />
            <button
              v-else
              class="flex-1 text-sm text-left capitalize text-n-slate-12 hover:underline"
              :title="t('KANBAN.EDITOR.RENAME')"
              @click="abrirEdicao(element)"
            >
              {{ humanize(element) }}
            </button>
            <span class="text-xs tabular-nums text-n-slate-10">
              {{ counts[element] || 0 }}
            </span>
            <button
              class="p-1 rounded-md disabled:opacity-30 disabled:cursor-not-allowed text-n-ruby-10 hover:bg-n-alpha-2"
              :disabled="!podeRemover(element)"
              :title="motivoBloqueio(element) || t('KANBAN.EDITOR.REMOVE')"
              @click="remover(element)"
            >
              <span class="i-lucide-trash-2 size-4" />
            </button>
          </li>
        </template>
      </Draggable>

      <div class="flex gap-2 mt-4">
        <input
          v-model="novoNome"
          type="text"
          class="flex-1"
          :placeholder="t('KANBAN.EDITOR.NEW_PLACEHOLDER')"
          @keyup.enter="adicionar"
        />
        <woot-button variant="smooth" :disabled="!novoNome.trim()" @click="adicionar">
          {{ t('KANBAN.EDITOR.ADD') }}
        </woot-button>
      </div>
      <p v-if="erro" class="mt-1 text-xs text-n-ruby-10">{{ erro }}</p>
      <p class="mt-2 text-xs text-n-slate-11">
        {{ t('KANBAN.EDITOR.HINT') }}
      </p>

      <div class="flex items-center justify-end gap-2 mt-8">
        <woot-button variant="clear" @click="emit('close')">
          {{ t('KANBAN.EDITOR.CANCEL') }}
        </woot-button>
        <woot-button :is-loading="isSaving" :disabled="!mudou" @click="salvar">
          {{ t('KANBAN.EDITOR.SAVE') }}
        </woot-button>
      </div>
    </div>
  </woot-modal>
</template>
