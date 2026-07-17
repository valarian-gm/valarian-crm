# Cria os custom attributes que o kanban de leads usa.
# Idempotente: pode rodar a cada deploy e a cada conta criada.
class Valarian::KanbanSetup
  # SEMPRE minusculo: Contacts::FilterService faz downcase nos valores e o SQL
  # aplica LOWER() — 'Nao Responde' nunca casaria no filtro.
  STAGES = %w[novo qualificado cliente nao_responde excluir].freeze

  def self.call(account)
    new(account).call
  end

  def initialize(account)
    @account = account
  end

  def call
    stage_attribute
    valor_contrato_attribute
    arquivado_attribute
    @account
  end

  private

  def stage_attribute
    attribute = find_or_init('stage')
    attribute.attribute_display_name = 'Estágio'
    attribute.attribute_description = 'Estágio do lead no funil (kanban)'
    # 'list' = um valor dentre opcoes fechadas. Editavel em Configuracoes ->
    # Atributos: adicionar valor = adicionar coluna no board, sem deploy.
    attribute.attribute_display_type = 'list'
    # Uniao: preserva estagios que o usuario criou na UI, so garante os padroes.
    attribute.attribute_values = (Array(attribute.attribute_values) | STAGES)
    attribute.save!
  end

  def valor_contrato_attribute
    attribute = find_or_init('valor_contrato')
    attribute.attribute_display_name = 'Valor do contrato'
    attribute.attribute_description = 'Valor fechado com o cliente (alimenta o evento de venda na Meta)'
    # 'number', NUNCA 'currency': FilterService::ATTRIBUTE_TYPES nao mapeia
    # currency, o cast SQL sai vazio ('::') e o filtro quebra. R$ formatado no front.
    attribute.attribute_display_type = 'number'
    attribute.save!
  end

  # Lead perdido. E ortogonal ao estagio de proposito: um lead pode estar
  # 'qualificado' E perdido — ele nao muda de coluna, so some da visao padrao.
  # Por isso NAO e um estagio.
  def arquivado_attribute
    attribute = find_or_init('arquivado')
    attribute.attribute_display_name = 'Arquivado'
    attribute.attribute_description = 'Lead perdido: fica oculto no board até ligar o filtro de arquivados'
    # checkbox mapeia pra 'boolean' em FilterService::ATTRIBUTE_TYPES — filtravel.
    attribute.attribute_display_type = 'checkbox'
    attribute.save!
  end

  def find_or_init(key)
    CustomAttributeDefinition.find_or_initialize_by(
      attribute_key: key,
      attribute_model: 'contact_attribute',
      account: @account
    )
  end
end
