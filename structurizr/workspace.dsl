workspace "BP Internet Banking" "Arquitectura de solución para el canal digital de banca por internet del Banco BP" {

    model {

        # ─────────────────────────────────────────────
        # ACTORES
        # ─────────────────────────────────────────────
        customer = person "Cliente BP" "Persona natural o jurídica que accede a los servicios de banca por internet para consultar movimientos, realizar transferencias y pagos." "Customer"

        backofficeUser = person "Operador Backoffice" "Equipo interno de BP que supervisa operaciones, fraude y monitoreo del canal digital." "Internal"

        # ─────────────────────────────────────────────
        # SISTEMA PRINCIPAL
        # ─────────────────────────────────────────────
        bpSystem = softwareSystem "BP Internet Banking" "Canal digital del banco BP. Permite a los clientes consultar saldos, historial de movimientos, realizar transferencias y pagos desde web y móvil." {

            # ── FRONTENDS ──────────────────────────────
            spa = container "SPA Web" "Aplicación web de página única para acceso desde navegador. Renderizado híbrido con SSR para carga inicial optimizada." "Next.js 14 / React 18" "Web Browser" {
                authModule        = component "Auth Module"          "Maneja el flujo OAuth2 Authorization Code + PKCE, gestión de tokens y cierre de sesión." "React Context + Axios"
                dashboardModule   = component "Dashboard Module"     "Vista principal: saldos, productos y accesos rápidos del cliente." "React"
                movementsModule   = component "Movements Module"     "Consulta y filtro del historial de movimientos con paginación virtual." "React + TanStack Query"
                transferModule    = component "Transfer Module"      "Formulario de transferencias propias e interbancarias con validación en tiempo real." "React Hook Form"
                notifModule       = component "Notifications Module" "Centro de notificaciones en tiempo real via WebSocket." "React"
            }

            mobileApp = container "Mobile App" "Aplicación móvil multiplataforma para iOS y Android. Incluye el flujo de Onboarding con reconocimiento facial." "Flutter 3.x / Dart" "Mobile App" {
                onboardingFlow    = component "Onboarding Flow"      "Flujo de vinculación de nuevo cliente: captura facial, liveness check y registro de credenciales." "Flutter + camera plugin"
                biometricAuth     = component "Biometric Auth"       "Autenticación local con FaceID, TouchID o PIN como método post-onboarding." "Flutter local_auth"
                mobileAuthModule  = component "Auth Module"          "Flujo OAuth2 Authorization Code + PKCE adaptado para cliente nativo móvil." "Flutter + http"
                mobileDashboard   = component "Dashboard Module"     "Vista principal móvil con saldos y accesos rápidos." "Flutter Widgets"
                mobileTransfer    = component "Transfer Module"      "Transferencias y pagos desde móvil." "Flutter"
            }

            # ── BFF LAYER ──────────────────────────────
            bffWeb = container "BFF Web" "Backend for Frontend exclusivo para la SPA. Agrega y adapta las respuestas de los microservicios al contrato esperado por el cliente web." "Node.js / Express" "BFF" {
                webAggregator     = component "Response Aggregator"  "Combina respuestas de múltiples servicios en una sola llamada (patron Aggregator)." "Express Middleware"
                webAuthFilter     = component "Auth Filter"          "Valida JWT emitido por Cognito en cada request entrante." "Express JWT"
                webRateLimit      = component "Rate Limiter"         "Control de tasa de peticiones por usuario/IP." "express-rate-limit"
            }

            bffMobile = container "BFF Mobile" "Backend for Frontend exclusivo para la app Flutter. Contratos optimizados para bajo ancho de banda y conexiones móviles intermitentes." "Node.js / Express" "BFF" {
                mobileAggregator  = component "Response Aggregator"  "Agrega respuestas adaptadas a los contratos del cliente móvil." "Express Middleware"
                mobileAuthFilter  = component "Auth Filter"          "Valida JWT y refresh token para sesiones móviles prolongadas." "Express JWT"
                pushGateway       = component "Push Gateway"         "Envía tokens de dispositivo al notification service para push notifications." "Express"
            }

            # ── API GATEWAY ────────────────────────────
            apiGateway = container "API Gateway" "Punto único de entrada para todos los microservicios internos. Gestiona routing, autenticación de servicio a servicio, throttling y logging." "AWS API Gateway + Kong" "API Gateway"

            # ── MICROSERVICIOS ─────────────────────────
            authService = container "Auth Service" "Delega autenticación a AWS Cognito. Maneja emisión, validación y rotación de tokens OAuth2." "Node.js / NestJS" "Microservice" {
                tokenController   = component "Token Controller"     "Endpoint de intercambio de código por token (Authorization Code Flow)." "NestJS Controller"
                refreshHandler    = component "Refresh Handler"      "Rotación automática de refresh tokens con invalidación de tokens anteriores." "NestJS Service"
                cognitoAdapter    = component "Cognito Adapter"      "Adaptador hacia AWS Cognito User Pools. Patrón Adapter para desacoplar del proveedor." "AWS SDK v3"
            }

            customerService = container "Customer Service" "Orquesta la información del cliente desde el Core Bancario y el Sistema Complementario. Patrón Facade para unificar las dos fuentes." "Java / Spring Boot" "Microservice" {
                customerFacade    = component "Customer Facade"      "Orquesta las llamadas al Core y al sistema complementario, unifica la respuesta." "Spring Service"
                coreAdapter       = component "Core Adapter"         "Adaptador de integración con la plataforma Core mediante REST/SOAP." "Spring RestTemplate"
                enrichmentAdapter = component "Enrichment Adapter"   "Adaptador al sistema complementario para datos en detalle del cliente." "Spring WebClient"
                customerCache     = component "Cache Manager"        "Cache-Aside sobre Redis: primero consulta caché, si miss va al origen y actualiza." "Spring Cache + Redis"
            }

            accountService = container "Account Service" "Gestión de productos y saldos del cliente." "Java / Spring Boot" "Microservice" {
                accountController = component "Account Controller"   "Expone saldos y productos del cliente." "Spring MVC"
                accountRepository = component "Account Repository"   "Acceso a datos de cuentas desde el Core." "Spring Data"
            }

            movementsService = container "Movements Service" "Historial de movimientos del cliente. Patrón CQRS: escritura delegada al Core, lectura desde réplica de lectura optimizada." "Java / Spring Boot" "Microservice" {
                queryHandler      = component "Query Handler"        "Lee movimientos desde la réplica de lectura (CQRS Read Side)." "Spring Service"
                commandHandler    = component "Command Handler"      "Delega escritura de movimientos al Core (CQRS Write Side)." "Spring Service"
                movementsRepo     = component "Movements Repository" "Acceso a la base de datos de lectura optimizada." "Spring Data JPA"
                eventPublisher    = component "Event Publisher"      "Publica evento MovementRegistered al bus de eventos para auditoría." "Spring Events + SQS"
            }

            transferService = container "Transfer Service" "Transferencias entre cuentas propias. Orquesta el flujo mediante patrón Saga para garantizar consistencia distribuida." "Java / Spring Boot" "Microservice" {
                transferSaga      = component "Transfer Saga"        "Orquesta los pasos de la transferencia: validar saldo, debitar, acreditar, notificar. Maneja compensación si algún paso falla." "Spring State Machine"
                transferValidator = component "Transfer Validator"   "Valida límites, saldo disponible y bloqueos de cuenta." "Spring Service"
                transferRepo      = component "Transfer Repository"  "Persistencia del estado de la saga." "Spring Data JPA"
                transferPublisher = component "Event Publisher"      "Publica TransferCompleted/Failed al bus de eventos." "SQS Publisher"
            }

            paymentService = container "Payment Service" "Pagos interbancarios mediante ACH Colombia y SWIFT. Flujo regulado con trazabilidad completa por normativa SFC." "Java / Spring Boot" "Microservice" {
                paymentSaga       = component "Payment Saga"         "Orquesta el flujo de pago interbancario con compensación ante fallos." "Spring State Machine"
                achAdapter        = component "ACH Adapter"          "Adaptador de integración con la red ACH Colombia." "Spring WebClient"
                swiftAdapter      = component "SWIFT Adapter"        "Adaptador de integración con red SWIFT para pagos internacionales." "Spring WebClient"
                paymentPublisher  = component "Event Publisher"      "Publica PaymentCompleted/Failed al bus de eventos." "SQS Publisher"
            }

            onboardingService = container "Onboarding Service" "Flujo de vinculación de nuevos clientes. Coordina reconocimiento facial, validación de identidad y registro en Cognito." "Node.js / NestJS" "Microservice" {
                livenessCheck     = component "Liveness Check"       "Invoca AWS Rekognition FaceSearch y CreateFaceLivenessSession para verificar que es una persona real." "AWS Rekognition SDK"
                identityValidator = component "Identity Validator"   "Compara rostro capturado con documento de identidad (cédula)." "NestJS Service"
                userProvisioning  = component "User Provisioning"    "Crea el usuario en Cognito User Pool y asigna grupo y atributos." "AWS Cognito SDK"
                biometricRegistry = component "Biometric Registry"   "Registra el template biométrico para futuras autenticaciones." "NestJS Service"
            }

            notificationService = container "Notification Service" "Envía notificaciones al cliente por múltiples canales. Garantiza entrega por al menos 2 canales según norma." "Node.js / NestJS" "Microservice" {
                notifRouter       = component "Notification Router"  "Decide qué canal(es) usar según preferencias del cliente y tipo de evento." "NestJS Service"
                snsChannel        = component "SNS Channel"          "Envío de SMS y Push Notifications vía AWS SNS." "AWS SNS SDK"
                sesChannel        = component "SES Channel"          "Envío de correos electrónicos transaccionales vía Amazon SES." "AWS SES SDK"
                twilioChannel     = component "Twilio Channel"       "Envío de mensajes WhatsApp y SMS como canal alternativo." "Twilio SDK"
                notifRepo         = component "Notification Log"     "Registro de notificaciones enviadas para auditoría y reintentos." "MongoDB"
            }

            auditService = container "Audit Service" "Registra todas las acciones del cliente de forma inmutable. Patrón Event Sourcing: cada evento es append-only, nunca se modifica." "Node.js / NestJS" "Microservice" {
                eventConsumer     = component "Event Consumer"       "Consume eventos del bus SQS/SNS: movimientos, transferencias, pagos, logins." "SQS Consumer"
                auditWriter       = component "Audit Writer"         "Persiste el evento en DynamoDB en modo append-only." "DynamoDB SDK"
                auditQueryApi     = component "Audit Query API"      "API de consulta para el backoffice. Solo lectura." "NestJS Controller"
            }

            # ── DATOS ──────────────────────────────────
            mainDb = container "Base de Datos Principal" "Base de datos relacional para datos de negocio: transferencias, pagos, estado de sagas." "Amazon RDS PostgreSQL Multi-AZ" "Database"

            movementsReadDb = container "Base de Datos de Lectura" "Réplica de lectura optimizada para consultas de movimientos (CQRS Read Side). Reduce carga sobre el Core." "Amazon RDS PostgreSQL Read Replica" "Database"

            auditDb = container "Base de Datos de Auditoría" "Almacenamiento inmutable de eventos de auditoría. Append-only, sin updates ni deletes. TTL configurado según normativa (10 años)." "Amazon DynamoDB" "Database"

            cacheLayer = container "Caché Distribuida" "Cache-Aside para datos de cliente frecuente. Reduce latencia y protege al Core de sobrecarga." "Amazon ElastiCache Redis" "Cache"

            notifDb = container "Base de Datos de Notificaciones" "Log de notificaciones enviadas para trazabilidad y reintentos." "Amazon DocumentDB (MongoDB)" "Database"

            # ── MENSAJERÍA ─────────────────────────────
            eventBus = container "Bus de Eventos" "Desacopla los microservicios productores de eventos de los consumidores. Garantiza entrega al menos una vez." "Amazon SQS + SNS (Fan-out)" "Message Bus"

            # ── CDN ────────────────────────────────────
            cdn = container "CDN" "Distribución de contenido estático de la SPA con baja latencia global. Cache de assets, HTTPS forzado." "Amazon CloudFront" "CDN"
        }

        # ─────────────────────────────────────────────
        # SISTEMAS EXTERNOS
        # ─────────────────────────────────────────────
        coreSystem = softwareSystem "Core Bancario" "Plataforma central del banco BP. Fuente de verdad de clientes, cuentas, productos y movimientos." "External"

        enrichmentSystem = softwareSystem "Sistema Complementario" "Sistema independiente que provee información detallada del cliente bajo demanda." "External"

        cognitoIdP = softwareSystem "AWS Cognito" "Identity Provider gestionado. Implementa OAuth2.0 / OIDC. Maneja User Pools, tokens y MFA." "External"

        rekognitionService = softwareSystem "AWS Rekognition" "Servicio de visión por computadora para liveness check y comparación facial durante el Onboarding." "External"

        achNetwork = softwareSystem "Red ACH Colombia" "Red de pagos de bajo valor interbancaria operada en Colombia. Regida por normativa Banco de la República." "External"

        swiftNetwork = softwareSystem "Red SWIFT" "Red global de mensajería financiera para pagos internacionales." "External"

        snsService = softwareSystem "Amazon SNS" "Servicio de notificaciones push y SMS de AWS." "External"
        sesService = softwareSystem "Amazon SES" "Servicio de correo electrónico transaccional de AWS." "External"
        twilioService = softwareSystem "Twilio" "Plataforma de comunicaciones para SMS y WhatsApp empresarial." "External"

        monitoringSystem = softwareSystem "AWS CloudWatch + X-Ray" "Observabilidad centralizada: métricas, logs, trazas distribuidas y alertas." "External"

        # ─────────────────────────────────────────────
        # RELACIONES — NIVEL CONTEXTO
        # ─────────────────────────────────────────────
        customer -> bpSystem "Consulta movimientos, realiza transferencias y pagos" "HTTPS"
        backofficeUser -> bpSystem "Supervisa operaciones y auditoría" "HTTPS"
        bpSystem -> coreSystem "Obtiene datos de cliente, cuentas y movimientos" "REST/HTTPS"
        bpSystem -> enrichmentSystem "Obtiene datos detallados del cliente" "REST/HTTPS"
        bpSystem -> cognitoIdP "Autentica y autoriza usuarios" "OAuth2 / OIDC"
        bpSystem -> rekognitionService "Verifica identidad facial en Onboarding" "HTTPS"
        bpSystem -> achNetwork "Procesa pagos interbancarios nacionales" "ISO 20022"
        bpSystem -> swiftNetwork "Procesa pagos internacionales" "SWIFT MT/MX"
        bpSystem -> snsService "Envía SMS y Push Notifications" "HTTPS"
        bpSystem -> sesService "Envía correos transaccionales" "SMTP/HTTPS"
        bpSystem -> twilioService "Envía mensajes WhatsApp y SMS alternativos" "HTTPS"
        bpSystem -> monitoringSystem "Emite métricas, logs y trazas" "CloudWatch SDK"

        # ─────────────────────────────────────────────
        # RELACIONES — NIVEL CONTENEDORES
        # ─────────────────────────────────────────────
        customer -> cdn "Accede a la SPA" "HTTPS"
        cdn -> spa "Sirve assets estáticos" "HTTPS"
        customer -> mobileApp "Usa la app móvil" "HTTPS"

        spa -> bffWeb "Llamadas API" "HTTPS / REST"
        mobileApp -> bffMobile "Llamadas API" "HTTPS / REST"

        bffWeb -> apiGateway "Rutea peticiones" "HTTPS"
        bffMobile -> apiGateway "Rutea peticiones" "HTTPS"

        apiGateway -> authService "Valida tokens" "HTTPS"
        apiGateway -> customerService "Consulta datos del cliente" "HTTPS"
        apiGateway -> accountService "Consulta saldos y productos" "HTTPS"
        apiGateway -> movementsService "Consulta movimientos" "HTTPS"
        apiGateway -> transferService "Ejecuta transferencias" "HTTPS"
        apiGateway -> paymentService "Ejecuta pagos interbancarios" "HTTPS"
        apiGateway -> onboardingService "Gestiona vinculación de cliente" "HTTPS"
        apiGateway -> auditService "Consulta auditoría (backoffice)" "HTTPS"

        authService -> cognitoIdP "Delega autenticación y emisión de tokens" "OAuth2 / OIDC"
        customerService -> coreSystem "Consulta datos básicos del cliente" "REST/HTTPS"
        customerService -> enrichmentSystem "Consulta datos en detalle" "REST/HTTPS"
        customerService -> cacheLayer "Lee y escribe datos de cliente frecuente" "Redis Protocol"
        accountService -> coreSystem "Consulta productos y saldos" "REST/HTTPS"
        movementsService -> coreSystem "Delega escritura de movimientos" "REST/HTTPS"
        movementsService -> movementsReadDb "Lee historial de movimientos" "JDBC"
        movementsService -> eventBus "Publica MovementRegistered" "SQS"
        transferService -> mainDb "Persiste estado de saga" "JDBC"
        transferService -> eventBus "Publica TransferCompleted/Failed" "SQS"
        paymentService -> achNetwork "Envía instrucción de pago ACH" "ISO 20022"
        paymentService -> swiftNetwork "Envía instrucción de pago SWIFT" "SWIFT MT"
        paymentService -> mainDb "Persiste estado de saga de pago" "JDBC"
        paymentService -> eventBus "Publica PaymentCompleted/Failed" "SQS"
        onboardingService -> rekognitionService "Verifica liveness y compara rostro" "HTTPS"
        onboardingService -> cognitoIdP "Registra nuevo usuario" "AWS SDK"
        notificationService -> eventBus "Consume eventos de negocio" "SQS"
        notificationService -> snsService "Envía push y SMS" "HTTPS"
        notificationService -> sesService "Envía emails" "SMTP"
        notificationService -> twilioService "Envía WhatsApp y SMS alternativos" "HTTPS"
        notificationService -> notifDb "Registra notificaciones enviadas" "MongoDB Protocol"
        auditService -> eventBus "Consume todos los eventos de negocio" "SQS"
        auditService -> auditDb "Persiste eventos en modo append-only" "DynamoDB SDK"
        mainDb -> movementsReadDb "Replicación continua" "RDS Replication"
    }

    views {

        systemContext bpSystem "C4-Contexto" {
            include *
            autoLayout tb
            title "C4 Nivel 1 — Diagrama de Contexto | BP Internet Banking"
            description "Vista de alto nivel para audiencia no técnica. Muestra el sistema BP y sus relaciones con actores y sistemas externos."
        }

        container bpSystem "C4-Contenedores" {
            include *
            autoLayout tb
            title "C4 Nivel 2 — Diagrama de Contenedores | BP Internet Banking"
            description "Vista técnica de los contenedores del sistema: aplicaciones, servicios, bases de datos y mensajería."
        }

        component spa "C4-Componentes-SPA" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes SPA Web | Next.js"
        }

        component mobileApp "C4-Componentes-Mobile" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes App Móvil | Flutter"
        }

        component transferService "C4-Componentes-Transfer" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes Transfer Service | Patrón Saga"
        }

        component movementsService "C4-Componentes-Movements" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes Movements Service | Patrón CQRS"
        }

        component auditService "C4-Componentes-Audit" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes Audit Service | Event Sourcing"
        }

        component onboardingService "C4-Componentes-Onboarding" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes Onboarding Service | Biometría"
        }

        component customerService "C4-Componentes-Customer" {
            include *
            autoLayout lr
            title "C4 Nivel 3 — Componentes Customer Service | Facade + Cache-Aside"
        }

        styles {
            element "Person" {
                shape Person
                background #1168bd
                color #ffffff
            }
            element "Internal" {
                shape Person
                background #0a5a8a
                color #ffffff
            }
            element "Software System" {
                background #1168bd
                color #ffffff
            }
            element "External" {
                background #999999
                color #ffffff
            }
            element "Container" {
                background #438dd5
                color #ffffff
            }
            element "Web Browser" {
                shape WebBrowser
                background #438dd5
                color #ffffff
            }
            element "Mobile App" {
                shape MobileDeviceLandscape
                background #438dd5
                color #ffffff
            }
            element "Database" {
                shape Cylinder
                background #438dd5
                color #ffffff
            }
            element "Cache" {
                shape Cylinder
                background #e06c00
                color #ffffff
            }
            element "Message Bus" {
                shape Pipe
                background #f0a500
                color #ffffff
            }
            element "API Gateway" {
                background #6b2d8b
                color #ffffff
            }
            element "BFF" {
                background #2d8b6b
                color #ffffff
            }
            element "CDN" {
                background #2d6b8b
                color #ffffff
            }
            element "Microservice" {
                background #2e7d32
                color #ffffff
            }
            element "Component" {
                background #85bbf0
                color #000000
            }
        }
    }
}
