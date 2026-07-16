# Customizacoes Valarian.
# Idempotente: pode rodar a cada deploy sem duplicar nada.
namespace :valarian do
  # Os estagios do kanban de leads.
  # SEMPRE minusculo: Contacts::FilterService faz downcase nos valores e o SQL
  # aplica LOWER() — 'Nao Responde' nunca casaria no filtro.
  KANBAN_STAGES = %w[novo qualificado cliente nao_responde excluir].freeze

  desc 'Cria os custom attributes do kanban de leads (stage, valor_contrato)'
  task setup_kanban: :environment do
    Account.find_each do |account|
      seed_stage(account)
      seed_valor_contrato(account)
      puts "  ✔ #{account.name} (##{account.id})"
    end
  end

  def seed_stage(account)
    attr = CustomAttributeDefinition.find_or_initialize_by(
      attribute_key: 'stage',
      attribute_model: 'contact_attribute',
      account: account
    )
    attr.attribute_display_name = 'Estágio'
    attr.attribute_description = 'Estágio do lead no funil (kanban)'
    # 'list' = valor unico dentre opcoes fechadas. Editavel depois em
    # Configuracoes -> Atributos: adicionar valor = adicionar coluna, sem deploy.
    attr.attribute_display_type = 'list'
    # Preserva estagios que o usuario tenha criado na UI; so garante os padroes.
    attr.attribute_values = (Array(attr.attribute_values) | KANBAN_STAGES)
    attr.save!
  end

  def seed_valor_contrato(account)
    attr = CustomAttributeDefinition.find_or_initialize_by(
      attribute_key: 'valor_contrato',
      attribute_model: 'contact_attribute',
      account: account
    )
    attr.attribute_display_name = 'Valor do contrato'
    attr.attribute_description = 'Valor fechado com o cliente (alimenta o evento de venda na Meta)'
    # 'number', NUNCA 'currency': FilterService::ATTRIBUTE_TYPES nao mapeia
    # currency, o cast SQL sai vazio ('::') e o filtro quebra. R$ e formatado no front.
    attr.attribute_display_type = 'number'
    attr.save!
  end
end
