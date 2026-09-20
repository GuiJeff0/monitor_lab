# Camada de Dados & Mensageria (`k8s/data`)

Este diretório hospedará os manifests da **Fase 2 do Roadmap**: persistência poliglota e broker de mensageria com armazenamento no HDD de 1TB (`local-hdd`).

## Serviços Planejados

- **PostgreSQL**: Banco relacional para pedidos e concorrência (`orders-service`).
- **RabbitMQ**: Message broker AMQP para processamento assíncrono orientado a eventos.
- **MongoDB**: Banco documental para catálogo de eventos e auditoria.
- **Redis**: Caching em memória para alta frequência e rate limit.
- **Elasticsearch**: Busca full-text indexada para catálogo de eventos.
