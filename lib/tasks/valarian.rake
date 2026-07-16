# Customizacoes Valarian.
#
# Pendura o setup do kanban no db:migrate — mesmo padrao que o Chatwoot usa em
# db_enhancements.rake pra carregar a installation config. Como o boot roda
# `db:chatwoot_prepare` (que chama db:migrate), os custom attributes se criam
# sozinhos a cada deploy. Ninguem precisa abrir console.
#
# Conta criada DEPOIS do boot (instalacao nova) e coberta pelo
# ValarianKanbanListener, que escuta ACCOUNT_CREATED.
Rake::Task['db:migrate'].enhance do
  if ActiveRecord::Base.connection.table_exists?('custom_attribute_definitions') &&
     ActiveRecord::Base.connection.table_exists?('accounts')
    Rake::Task['valarian:setup_kanban'].invoke
  end
end

namespace :valarian do
  desc 'Cria os custom attributes do kanban de leads (stage, valor_contrato)'
  task setup_kanban: :environment do
    Account.find_each do |account|
      Valarian::KanbanSetup.call(account)
      puts "  ✔ kanban pronto: #{account.name} (##{account.id})"
    end
  end
end
