# Frontend Engineering Skills & Guidelines — Ticket Booking System

> **Stack:** Next.js 15+ (App Router), React 19, TypeScript, Vanilla CSS / Modern CSS Modules, TanStack Query v5, Zustand, OpenTelemetry Web / RUM.  
> **Domínio:** Interface Web de Alta Concorrência para Venda de Ingressos de Estádios de Futebol e Arenas (`ticket-web`).

---

## 1. Visão Geral das Competências e Papel

O engenheiro front-end neste ecossistema é responsável por construir uma aplicação web ultrarrápida, resiliente a picos massivos de tráfego (*flash sales* / abertura de vendas de clássicos e finais de campeonatos) e integrada aos padrões de observabilidade ponta a ponta do laboratório.

```mermaid
flowchart TD
    subgraph Frontend["ticket-web (Next.js 15 App Router)"]
        UI["UI Layer (React 19 / Server & Client Components)"]
        State["State Management (TanStack Query v5 + Zustand)"]
        OTelRUM["OTel Web SDK (Tracing + Web Vitals + RUM)"]
    end

    subgraph Edge["Gateway & Ingress"]
        Traefik["Traefik v3 (TLS Termination)"]
        BFF["FastAPI BFF (API Gateway :8000)"]
    end

    subgraph Observability["Monitor Lab"]
        Tempo[("Grafana Tempo (Traces :4318)")]
        Loki[("Grafana Loki (Frontend Logs)")]
    end

    UI --> State
    State -->|HTTP Fetch com traceparent & X-Correlation-ID| Traefik --> BFF
    OTelRUM -.->|OTLP HTTP :4318 (Spans)| Tempo
    OTelRUM -.->|Structured Error Logs| Loki
```

---

## 2. Matriz de Habilidades Obrigatórias (Core Skills)

### 2.1 Padrões de Alta Concorrência na UI/UX
- **Contagem Regressiva Atômica (Reservation Lock TTL):** Manter timer regressivo sincronizado com o backend (10 minutos) sem drift de clock local (`performance.now()` ou timestamp absoluto retornado pelo BFF).
- **Tratamento Elegante de Conflitos (*Sold Out* / 409 Conflict):** Feedback imediato e amigável quando um setor esgota durante a finalização do pedido.
- **Polling Resiliente e Backoff:** Estratégia de consulta inteligente na tela de processamento de pagamento (`/checkout/processing/[orderId]`) com limite de tentativas e retry exponencial.
- **Prevenção de Cliques Duplos (Double Submission):** Desabilitação de botões de compra e geração de `idempotency_key` (UUID v4) no client antes de enviar a requisição de pagamento.

### 2.2 Observabilidade Frontend & Real User Monitoring (RUM)
- **Propagação de Contexto W3C no Browser:** Injeção automática dos headers `traceparent` e `X-Correlation-ID` em todas as chamadas HTTP via interceptor do fetch.
- **Core Web Vitals:** Monitoramento contínuo de **LCP** (< 2.5s), **INP** (< 200ms) e **CLS** (< 0.1).
- **Error Boundary com Telemetria:** Captura de exceções React e envio de logs estruturados em JSON contendo `trace_id` e stack trace para o Loki.

### 2.3 Mapa Visual e Interativo do Estádio
- Renderização vetorial responsiva (SVG interativo ou Canvas) dos setores do estádio (Norte, Sul, Leste, Oeste, Camarotes).
- Destaque dinâmico de cores de acordo com o status do setor:
  - 🟢 **Disponível:** Verde / Azul (> 20% de vagas)
  - 🟡 **Últimos Ingressos:** Laranja (< 20% de vagas)
  - 🔴 **Esgotado:** Cinza / Vermelho (0 vagas — desabilitado para clique)
- Tooltip com capacidade restante em tempo real e preço do ingresso.

### 2.4 Gerenciamento de Estado & Cache
- **Server State (TanStack Query v5):** Cache de catálogo, deduplicação de requisições e *stale-while-revalidate* para buscas e detalhes de eventos.
- **Client State (Zustand):** Carrinho de ingressos da sessão, setor selecionado e preferências de visualização.

---

## 3. Padrões de Código e Estrutura do Projeto

```text
ticket-web/
├── app/                              # Next.js App Router
│   ├── (auth)/                       # Route Group: Autenticação
│   │   ├── login/page.tsx
│   │   └── register/page.tsx
│   ├── (shop)/                       # Route Group: Fluxo de Compra
│   │   ├── page.tsx                  # Home (Eventos em Destaque)
│   │   ├── search/page.tsx           # Busca Facetada
│   │   ├── events/[slug]/page.tsx    # Detalhes & Mapa do Estádio
│   │   ├── checkout/[orderId]/page.tsx # Pagamento & Timer
│   │   └── checkout/processing/[orderId]/page.tsx
│   ├── profile/                      # Perfil e Meus Ingressos
│   │   ├── page.tsx
│   │   └── orders/[orderId]/page.tsx # E-Ticket / QR Code
│   ├── layout.tsx                    # Root Layout + Providers
│   └── error.tsx                     # Global Error Boundary com OTel
│
├── components/
│   ├── ui/                           # Componentes base (Button, Card, Modal, Badge, Toast)
│   ├── stadium/                      # Componentes do Estádio (StadiumMap, SectorSelector, SeatCounter)
│   ├── checkout/                     # CountdownTimer, PaymentForm, OrderSummary
│   └── telemetry/                    # OTelProvider, WebVitalsTracker
│
├── hooks/                            # Custom Hooks (useCountdown, useOrderPolling, useAuth)
├── services/                         # Clientes HTTP (BFF API Client com OTel headers)
├── stores/                           # Zustand Stores (useCartStore, useAuthStore)
├── types/                            # TypeScript Definitions (Event, Sector, Order, Payment)
├── styles/                           # Design Tokens & Global CSS
├── telemetry/                        # Configuração do OpenTelemetry Web SDK
├── Dockerfile                        # Multi-stage Standalone Build
└── README.md
```

---

## 4. Padrão de Chamada HTTP com Contexto de Telemetria

Toda requisição feita do navegador para o **FastAPI BFF** deve injetar o Correlation ID e herdar o Trace Context ativo:

```typescript
// services/apiClient.ts
import { trace, context } from '@opentelemetry/api';

export async function fetchWithTelemetry(url: string, options: RequestInit = {}) {
  const correlationId = crypto.randomUUID();
  const activeSpan = trace.getSpan(context.active());
  
  const headers = new Headers(options.headers || {});
  headers.set('X-Correlation-ID', correlationId);
  headers.set('Content-Type', 'application/json');

  if (activeSpan) {
    const traceId = activeSpan.spanContext().traceId;
    const spanId = activeSpan.spanContext().spanId;
    // W3C Traceparent: version-trace_id-span_id-flags
    headers.set('traceparent', `00-${traceId}-${spanId}-01`);
  }

  const response = await fetch(url, { ...options, headers });
  
  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    console.error('[API Error]', {
      url,
      status: response.status,
      correlationId,
      errorData,
    });
  }

  return response;
}
```

---

## 5. Checklist de Qualidade do Front-End

- [ ] **Next.js 15 Standalone Build:** Imagem Docker otimizada (< 150MB).
- [ ] **Tipagem Estrita:** TypeScript com `noImplicitAny: true` e validações de input via Zod.
- [ ] **Sincronização de Timer de Reserva:** Sem perda de contagem regressiva em caso de refresh na tela de checkout.
- [ ] **Acessibilidade (a11y):** Navegação completa por teclado no mapa de setores e contraste WCAG AA.
- [ ] **Responsividade:** Experiência mobile fluida (compra de ingresso na fila do estádio em 3 toques).
- [ ] **RUM & Traces Ativos:** Spans de navegação e requisições visíveis no Grafana Tempo.
