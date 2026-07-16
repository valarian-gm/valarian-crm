# Garante os custom attributes do kanban assim que uma conta nasce.
#
# Sem isto, numa instalacao nova a conta so existe DEPOIS do boot — entao a rake
# do deploy (que roda via db:migrate) nao acha conta nenhuma e o board sobe sem
# os atributos. Com o listener, o setup acontece no exato momento do signup.
class ValarianKanbanListener < BaseListener
  def account_created(event)
    account = event.data[:account]
    return if account.blank?

    Valarian::KanbanSetup.call(account)
  rescue StandardError => e
    # Nunca derrubar a criacao da conta por causa do kanban.
    Rails.logger.error("[valarian] falha ao preparar kanban da conta #{account&.id}: #{e.message}")
  end
end
