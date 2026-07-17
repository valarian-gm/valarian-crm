import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';

/**
 * Resolve o rotulo de uma etapa do kanban.
 *
 * A CHAVE e estavel (o codigo depende de 'novo'/'cliente' e os contatos guardam
 * a chave em custom_attributes.stage). O ROTULO e so apresentacao e pode ser
 * editado a vontade — renomear nunca orfana lead nem quebra regra.
 *
 * Precedencia:
 *   1. rotulo customizado da conta (custom_attributes.kanban_stage_labels)
 *   2. traducao padrao (KANBAN.STAGES.*) — so existe pras etapas de fabrica
 *   3. a propria chave humanizada ('em_negociacao' -> 'em negociacao')
 */
export function useStageLabels() {
  const { t } = useI18n();
  const getAccount = useMapGetter('accounts/getAccount');
  const accountId = useMapGetter('getCurrentAccountId');

  const customLabels = computed(
    () => getAccount.value(accountId.value)?.custom_attributes?.kanban_stage_labels || {}
  );

  const stageLabel = stage => {
    if (!stage) return '';
    const custom = customLabels.value[stage];
    if (custom) return custom;
    return t(`KANBAN.STAGES.${stage.toUpperCase()}`, stage.replace(/_/g, ' '));
  };

  return { stageLabel, customLabels };
}
