FactoryBot.define do
  factory :message_reaction do
    message
    association :actor, factory: :user
    emoji { '👍' }
    account { message&.account }
  end
end
