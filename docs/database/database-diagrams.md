# Modelagem de Dados e Diagramas de Relacionamento (ER)

> **Documento:** Modelagem Completa de Banco de Dados — Ticket Booking System  
> **Escopo:** PostgreSQL (Transacional / Estádio por Setores), MongoDB (Catálogo & Auditoria) e Elasticsearch (Busca Textual e Filtros Facetados).

---

## 1. Visão Geral da Persistência Poliglota

O ecossistema utiliza uma estratégia de **Persistência Poliglota** onde cada banco de dados atende a um padrão de acesso e garantia de consistência específico:

```mermaid
flowchart TD
    subgraph PostgreSQL["PostgreSQL 16 (Cluster Compartilhado - ACID)"]
        direction TB
        Auth["auth_users"]
        User["users"]
        Addr["user_addresses"]
        Orders["orders"]
        Items["order_items"]
        Sectors["sectors"]
        Seats["seats"]
        Payments["payments"]
    end

    subgraph MongoDB["MongoDB 7 (Document Store)"]
        direction TB
        CollEvents["events (Catálogo de Jogos/Shows)"]
        CollNotif["notifications (Histórico de Envios)"]
        CollAudit["audit_logs (Trilhas de Auditoria)"]
    end

    subgraph Elasticsearch["Elasticsearch 8 (Search Engine)"]
        direction TB
        IdxEvents["events (Índice de Busca Full-Text e Filtros)"]
    end

    Auth -->|1:1| User -->|1:N| Addr
    Orders -->|1:N| Items -->|N:1| Sectors -->|1:N| Seats
    Orders -->|1:N| Seats
    Orders -->|1:1| Payments

    CollEvents -.->|"Sincronização via RabbitMQ"| IdxEvents
    Sectors -.->|"Sincronização de Vagas"| IdxEvents
```

---

## 2. PostgreSQL — Diagrama Entidade-Relacionamento Completo (ER)

O modelo relacional modela a venda de ingressos de **Estádios de Futebol** e arenas multiuso, onde a capacidade total é dividida por **Setores** (ex: *Arquibancada Norte*, *Cadeira Inferior Sul*, *Camarotes*) com controle de estoque e assentos individuais/contagem atômica.

```mermaid
erDiagram
    auth_users ||--|| users : "1:1 possui perfil"
    users ||--o{ user_addresses : "1:N possui endereços"
    users ||--o{ orders : "1:N realiza pedidos"
    
    events_ref ||--o{ sectors : "1:N possui setores"
    sectors ||--o{ seats : "1:N contém assentos"
    sectors ||--o{ order_items : "1:N compõe itens"
    
    orders ||--o{ order_items : "1:N contém itens"
    orders ||--o{ seats : "1:N reserva assentos"
    orders ||--o| payments : "1:1 transaciona pagamento"

    auth_users {
        uuid id PK "Identificador único da conta"
        varchar email UK "Email único de login"
        varchar password_hash "Hash bcrypt da senha"
        boolean is_active "Status da conta"
        timestamptz created_at "Data de criação"
        timestamptz updated_at "Data de atualização"
    }

    users {
        uuid id PK "Identificador único do perfil"
        uuid auth_id FK "Chave estrangeira para auth_users"
        varchar full_name "Nome completo"
        varchar phone "Telefone de contato"
        varchar document UK "CPF / Documento único"
        timestamptz created_at "Data de cadastro"
    }

    user_addresses {
        uuid id PK "Identificador do endereço"
        uuid user_id FK "Chave estrangeira para users"
        varchar street "Logradouro e número"
        varchar city "Cidade"
        varchar state "Estado (UF)"
        varchar zip_code "CEP"
        boolean is_default "Endereço principal"
    }

    sectors {
        uuid id PK "Identificador do setor"
        uuid event_id "Referência ao evento/jogo"
        varchar name "Nome (ex: Cadeira Inferior Leste)"
        int capacity "Capacidade total do setor"
        int available_seats "Assentos disponíveis (tempo real)"
        decimal price "Preço base do ingresso no setor"
        timestamptz created_at "Criação"
        timestamptz updated_at "Atualização"
    }

    seats {
        uuid id PK "Identificador único do assento"
        uuid event_id "Identificador do evento"
        uuid sector_id FK "Chave estrangeira para sectors"
        varchar seat_number "Número do assento (ex: LESTE-A-102)"
        varchar status "AVAILABLE | RESERVED | SOLD"
        uuid order_id FK "Chave estrangeira para orders (NULL)"
        uuid reserved_by "ID do usuário da reserva (NULL)"
        timestamptz reserved_until "TTL da reserva de 10 min (NULL)"
        int version "Controle de concorrência otimista"
    }

    orders {
        uuid id PK "Identificador único do pedido"
        uuid user_id FK "Chave estrangeira para users"
        uuid event_id "Identificador do jogo/evento"
        varchar status "CREATED | RESERVED | PROCESSING | CONFIRMED | CANCELLED | EXPIRED"
        decimal total_amount "Valor total do pedido"
        timestamptz created_at "Data de criação"
        timestamptz expires_at "Data limite para pagamento (10 min)"
    }

    order_items {
        uuid id PK "Identificador do item"
        uuid order_id FK "Chave estrangeira para orders"
        uuid sector_id FK "Chave estrangeira para sectors"
        int quantity "Quantidade de ingressos"
        decimal unit_price "Preço unitário no momento da compra"
        decimal subtotal "Valor total do item"
    }

    payments {
        uuid id PK "Identificador do pagamento"
        uuid order_id FK "Chave estrangeira para orders (UK)"
        varchar idempotency_key UK "Chave única de idempotência"
        decimal amount "Valor cobrado"
        varchar currency "Moeda (BRL)"
        varchar status "PROCESSING | SUCCESS | FAILED"
        varchar gateway_charge_id "ID retornado pelo gateway"
        timestamptz created_at "Data da tentativa"
        timestamptz updated_at "Data da confirmação"
    }
```

---

## 3. Modelo do Estádio de Futebol (Divisão de Capacidade)

```mermaid
flowchart TD
    subgraph Estadio["🏟️ Estádio (Capacidade Total: 50.000 Lugares)"]
        direction TB
        S_Norte["🔴 Setor Norte (Geral / Arquibancada)<br/>Capacidade: 15.000 lugares<br/>Preço: R$ 50,00"]
        S_Sul["🔵 Setor Sul (Visitante / Arquibancada)<br/>Capacidade: 10.000 lugares<br/>Preço: R$ 50,00"]
        S_Leste_Inf["🟡 Setor Leste Inferior (Cadeiras)<br/>Capacidade: 12.000 lugares<br/>Preço: R$ 120,00"]
        S_Oeste_VIP["🟣 Setor Oeste VIP / Camarotes<br/>Capacidade: 13.000 lugares<br/>Preço: R$ 250,00"]
    end

    subgraph ReservaAtomica["Fluxo de Reserva de Alta Concorrência"]
        Query["SELECT * FROM seats<br/>WHERE sector_id = $sector_id AND status = 'AVAILABLE'<br/>LIMIT $qty FOR UPDATE SKIP LOCKED"]
    end

    S_Norte & S_Sul & S_Leste_Inf & S_Oeste_VIP -->|Aloca Assentos| Query
```

---

## 4. MongoDB — Schemas das Coleções

O MongoDB armazena dados semiesquematizados de catálogo de eventos com documentos embutidos e logs de auditoria de alta vazão:

```mermaid
classDiagram
    class EventDocument {
        +ObjectId _id
        +string title "ex: Flamengo vs Palmeiras - Final"
        +string description "Detalhes da partida"
        +string category "FUTEBOL | SHOW | TEATRO"
        +string venue "Maracanã, Rio de Janeiro"
        +ISODate start_time "2026-09-15T19:00:00Z"
        +ISODate end_time "2026-09-15T21:30:00Z"
        +string status "ACTIVE | CANCELLED | SOLD_OUT"
        +SectorEmbedded[] sectors
        +ISODate created_at
        +ISODate updated_at
    }

    class SectorEmbedded {
        +string id "uuid"
        +string name "Setor Norte"
        +int capacity 15000
        +double price 50.00
    }

    class NotificationDocument {
        +ObjectId _id
        +string user_id "uuid"
        +string order_id "uuid"
        +string channel "EMAIL | SMS | PUSH"
        +string type "ORDER_CONFIRMED | PAYMENT_FAILED"
        +string recipient "usuario@email.com"
        +NotificationPayload payload
        +string status "SENT | FAILED"
        +ISODate created_at
        +ISODate sent_at
        +string error_reason
    }

    class NotificationPayload {
        +string subject "Seu ingresso foi confirmado!"
        +string body "Detalhes do QR Code e setor..."
        +string qr_code_url "https://..."
    }

    class AuditLogDocument {
        +ObjectId _id
        +string entity "Order | Payment | Seat"
        +string entity_id "uuid"
        +string action "SEATS_LOCKED | CHARGE_SUCCESS"
        +string actor "orders-service | payment-service"
        +ISODate timestamp
        +AuditMetadata metadata
    }

    class AuditMetadata {
        +string trace_id "OTel W3C Trace ID"
        +string span_id "OTel Span ID"
        +string correlation_id "Business Correlation ID"
        +object payload_snapshot
    }

    EventDocument *-- SectorEmbedded
    NotificationDocument *-- NotificationPayload
    AuditLogDocument *-- AuditMetadata
```

---

## 5. Elasticsearch — Mapeamento do Índice `events`

O Elasticsearch é otimizado para busca textual com autocompletar e filtros facetados (hoje, próxima semana, faixa de preço, setor):

```mermaid
classDiagram
    class EventsIndexMapping {
        +keyword id
        +text title "Analyzer: autocomplete (edge_ngram)"
        +text description "Analyzer: standard"
        +keyword category "Faceting"
        +keyword venue
        +geo_point location "Lat/Lon para busca por raio"
        +date date "Filtro: hoje / próxima semana"
        +integer available_seats "Contagem em tempo real"
        +SectorNested[] sectors "Nested Object"
        +PriceRange price_range
        +keyword status
        +long version "Controle de versão para upsert idempotente"
    }

    class SectorNested {
        +keyword id
        +text name
        +double price
        +integer available_seats
    }

    class PriceRange {
        +scaled_float min
        +scaled_float max
    }

    EventsIndexMapping *-- SectorNested
    EventsIndexMapping *-- PriceRange
```

---

## 6. Diagrama de Sincronização Cross-Database

Como os dados fluem e sincronizam de forma orientada a eventos via **RabbitMQ**:

```mermaid
sequenceDiagram
    autonumber
    participant Admin as Gestão de Eventos
    participant Mongo as MongoDB (Catálogo)
    participant RMQ as RabbitMQ (Exchanges)
    participant SyncWorker as Search Sync Worker (Go)
    participant ES as Elasticsearch (Índice)
    participant Orders as Orders Service (Go)
    participant PG as PostgreSQL (Seats/Orders)

    Note over Admin,ES: === Cadastro e Atualização de Jogo/Evento ===
    Admin->>Mongo: Inserir Documento Evento (com Setores)
    Mongo-->>Admin: Evento Salvo (_id: 64a8...)
    Admin->>RMQ: Publica "event.created" { event_id, title, sectors[] }
    RMQ->>SyncWorker: Consome "event.created"
    SyncWorker->>ES: PUT /events/_doc/{id} (Indexação com Autocomplete Mapping)
    ES-->>SyncWorker: 201 Created

    Note over PG,ES: === Reserva de Assento e Atualização de Estoque ===
    Orders->>PG: BEGIN; SELECT ... FOR UPDATE SKIP LOCKED; UPDATE seats; COMMIT;
    Orders->>RMQ: Publica "seats.status_changed" { event_id, sector_id, delta: -2 }
    RMQ->>SyncWorker: Consome "seats.status_changed"
    SyncWorker->>ES: POST /events/_update/{id} (Script decrementa available_seats)
    ES-->>SyncWorker: 200 OK (Filtros de busca atualizados)
```

---

## 7. Diagramas de Máquinas de Estados (Lifecycle)

### 7.1 Ciclo de Vida do Pedido (`orders.status`)
```mermaid
stateDiagram-v2
    [*] --> CREATED: FastAPI BFF recebe requisição
    CREATED --> RESERVED: Orders Service aloca assentos (SKIP LOCKED)
    CREATED --> CANCELLED: Assentos esgotados / conflito
    RESERVED --> PAYMENT_PROCESSING: Mensagem enviada para payment-service
    RESERVED --> EXPIRED: TTL de 10 min expirou sem pagamento
    PAYMENT_PROCESSING --> CONFIRMED: Gateway confirma pagamento (200 OK)
    PAYMENT_PROCESSING --> PAYMENT_FAILED: Cartão recusado / saldo insuficiente
    PAYMENT_FAILED --> RESERVED: Tentativa com outro método (dentro do TTL)
    PAYMENT_FAILED --> CANCELLED: Tentativas esgotadas
    EXPIRED --> [*]
    CONFIRMED --> [*]
    CANCELLED --> [*]
```

### 7.2 Ciclo de Vida do Assento (`seats.status`)
```mermaid
stateDiagram-v2
    [*] --> AVAILABLE: Setor cadastrado
    AVAILABLE --> RESERVED: SELECT FOR UPDATE SKIP LOCKED (TTL 10 min)
    RESERVED --> SOLD: Pedido CONFIRMED (Pagamento Aprovado)
    RESERVED --> AVAILABLE: Pedido EXPIRED / CANCELLED (Rollback)
    SOLD --> AVAILABLE: Reembolso / Cancelamento de ingresso
    SOLD --> [*]
```

### 7.3 Ciclo de Vida do Pagamento (`payments.status`)
```mermaid
stateDiagram-v2
    [*] --> PROCESSING: Recebe order_id + idempotency_key
    PROCESSING --> SUCCESS: Gateway charge aprovado
    PROCESSING --> FAILED: Gateway charge recusado / Timeout
    SUCCESS --> [*]
    FAILED --> [*]
```

---

## 8. Dicionário de Dados e Índices Recomendados

### 8.1 Índices de Alta Performance no PostgreSQL
```sql
-- Busca rápida de login por email
CREATE UNIQUE INDEX idx_auth_users_email ON auth_users(email);

-- Busca de perfil por CPF/Documento e FK de autenticação
CREATE UNIQUE INDEX idx_users_document ON users(document);
CREATE INDEX idx_users_auth_id ON users(auth_id);

-- Busca de endereços por usuário
CREATE INDEX idx_user_addresses_user_id ON user_addresses(user_id);

-- Hot-Path da compra de ingressos: Bloqueio de assentos livres por setor
CREATE INDEX idx_seats_locking ON seats(event_id, sector_id, status) 
WHERE status = 'AVAILABLE';

-- Histórico de pedidos do usuário
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);

-- Idempotência e consulta de pagamentos por pedido
CREATE UNIQUE INDEX idx_payments_idempotency ON payments(idempotency_key);
CREATE INDEX idx_payments_order_id ON payments(order_id);
```

### 8.2 Índices no MongoDB
```javascript
// Busca de eventos por categoria e data
db.events.createIndex({ category: 1, start_time: 1 });
db.events.createIndex({ status: 1 });

// Consulta de notificações por usuário e pedido
db.notifications.createIndex({ user_id: 1, created_at: -1 });
db.notifications.createIndex({ order_id: 1 });

// Auditoria por entidade e timestamp
db.audit_logs.createIndex({ entity: 1, entity_id: 1 });
db.audit_logs.createIndex({ "metadata.trace_id": 1 });
```
