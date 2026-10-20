# API de E-commerce Segura con Swagger Completo

API REST construida con **Laravel 12**, **JWT** (tymon/jwt-auth), **Stripe** (pagos) y **Swagger/OpenAPI** (l5-swagger), corriendo sobre **MySQL 8** en Docker.

> 📦 **Este README documenta la API como proyecto.** Para levantar el ecosistema completo
> (frontend + API + MySQL) con Docker, usa el **README de la raíz del repositorio**: ahí están
> las instrucciones vigentes (puerto `8000`, servicios `backend`/`nginx`/`db`, `.env` único).

## Contenido del proyecto

```
app/Http/Controllers/Api/   -> AuthController, ProductController, OrderController, PaymentController
app/Http/Requests/          -> Form Requests (validación)
app/Models/                 -> User, Product, Order, OrderItem, Payment
app/Services/StripeService.php
database/migrations/        -> users, products, orders, order_items, payments
database/seeders/           -> Admin, cliente demo y 10+ productos de ejemplo
routes/api.php               -> Todas las rutas de la API
Dockerfile, docker/                         -> Imagen (PHP-FPM + Nginx, multi-stage)
```

## Cómo levantarla

Desde la **raíz del repositorio** (no desde esta carpeta):

```bash
cp .env.example .env      # completa STRIPE_SECRET, STRIPE_PUBLISHABLE_KEY y las contraseñas
docker compose up -d --build
```

Al arrancar, el contenedor `backend` espera a MySQL, corre las migraciones, siembra los datos
de demostración y genera la documentación Swagger. Quedan disponibles:

- API: `http://localhost:8000/api/...`
- Swagger UI: `http://localhost:8000/api/documentation`
- phpMyAdmin (opcional): `docker compose --profile tools up -d` y luego `http://localhost:8081`

**Stripe (modo test):** llaves en https://dashboard.stripe.com/test/apikeys → en el `.env` de la
raíz (`STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET`). **Webhook (opcional):** apúntalo a
`http://TU_DOMINIO_PUBLICO:8000/api/payments/webhook` (en local, `stripe listen` o `ngrok`),
eventos `payment_intent.succeeded` y `payment_intent.payment_failed`, y copia el *Signing secret*
a `STRIPE_WEBHOOK_SECRET`.

> **APP_KEY / JWT_SECRET:** si los dejas vacíos se generan claves temporales (cambian en cada
> reinicio e invalidan los tokens). Para que persistan, defínelos en el `.env`
> (ver comandos en `.env.example`).

## Usuarios de prueba (creados por el seeder)

| Rol      | Email                | Password     |
|----------|-----------------------|--------------|
| Admin    | admin@example.com     | Admin123!    |
| Cliente  | cliente@example.com   | Cliente123!  |

## Flujo típico de prueba

```bash
# 1) Login
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"cliente@example.com","password":"Cliente123!"}'
# -> copiar el access_token de la respuesta

# 2) Ver catálogo (público, no requiere token)
curl http://localhost:8000/api/products

# 3) Crear una orden
curl -X POST http://localhost:8000/api/orders \
  -H "Authorization: Bearer TU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"items":[{"product_id":1,"quantity":2}]}'

# 4) Crear el PaymentIntent en Stripe para esa orden
curl -X POST http://localhost:8000/api/payments/create-intent \
  -H "Authorization: Bearer TU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"order_id":1}'
# -> usar el client_secret devuelto en el frontend (Stripe.js / Stripe Elements)
#    para completar el pago con una tarjeta de prueba, ej. 4242 4242 4242 4242

# 5) Confirmar/consultar el estado del pago
curl -X POST http://localhost:8000/api/payments/confirm \
  -H "Authorization: Bearer TU_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"payment_intent_id":"pi_..."}'

# 6) Ver historial de compras
curl http://localhost:8000/api/orders -H "Authorization: Bearer TU_TOKEN"
```

## Endpoints principales

| Método | Ruta                          | Auth        | Descripción                              |
|--------|--------------------------------|-------------|-------------------------------------------|
| POST   | /api/auth/register             | No          | Registro de cliente                       |
| POST   | /api/auth/login                | No          | Login, devuelve JWT                       |
| POST   | /api/auth/logout               | Sí          | Invalida el token                         |
| POST   | /api/auth/refresh              | Sí          | Refresca el token                         |
| GET    | /api/auth/me                   | Sí          | Datos del usuario autenticado             |
| GET    | /api/products                  | No          | Listado público de productos              |
| GET    | /api/products/{id}              | No          | Detalle de un producto                    |
| POST   | /api/products                  | Sí (admin)  | Crear producto                            |
| PUT    | /api/products/{id}              | Sí (admin)  | Editar producto                           |
| DELETE | /api/products/{id}              | Sí (admin)  | Eliminar producto                         |
| POST   | /api/orders                    | Sí          | Crear orden de compra                     |
| GET    | /api/orders                    | Sí          | Historial de compras del usuario          |
| GET    | /api/orders/{id}                 | Sí          | Detalle de una orden                       |
| POST   | /api/payments/create-intent    | Sí          | Crear PaymentIntent de Stripe             |
| POST   | /api/payments/confirm          | Sí          | Confirmar estado del pago                 |
| POST   | /api/payments/webhook          | No*         | Webhook de Stripe (*validado por firma)   |

Toda la documentación interactiva (probar cada endpoint desde el navegador) está en
`/api/documentation`.

## Si ves "502/503 Bad Gateway"

Nginx no logra hablar con PHP-FPM, normalmente porque el contenedor `backend` aún está
arrancando (espera a MySQL y corre migraciones) o terminó con un error:

```bash
docker compose ps
docker compose logs backend
```

## Comandos útiles

```bash
# Ver logs
docker compose logs -f backend

# Entrar al contenedor
docker compose exec backend sh

# Volver a correr migraciones/seeders manualmente
docker compose exec backend php artisan migrate:fresh --seed

# Regenerar documentación Swagger tras cambiar anotaciones
docker compose exec backend php artisan l5-swagger:generate

# Apagar todo
docker compose down

# Apagar y borrar datos de MySQL
docker compose down -v
```

## Arquitectura de seguridad implementada

- Autenticación **JWT** (guard `api`), tokens con expiración (`JWT_TTL`) y refresh.
- Autorización por rol: middleware `is.admin` protege creación/edición/borrado de productos.
- Cada orden y pago valida que pertenezca al usuario autenticado (o sea admin).
- Validación de entrada centralizada en **Form Requests**, con mensajes de error en español.
- Manejo de errores homogéneo en JSON (`bootstrap/app.php` -> `withExceptions`), sin exponer
  trazas de error en producción (`APP_DEBUG=false`).
- Verificación de firma de los webhooks de Stripe (`Stripe\Webhook::constructEvent`) antes de
  procesar cualquier evento.
- Transacciones de base de datos con bloqueo de fila (`lockForUpdate`) al crear órdenes, para
  evitar condiciones de carrera sobre el stock.
- Passwords hasheados con bcrypt, nunca expuestos en las respuestas (`$hidden` en el modelo `User`).

## Notas de versiones

Se usan versiones compatibles y estables al momento de escribir esto: Laravel ^12,
tymon/jwt-auth ^2.1 (compatible con Laravel 11/12), stripe/stripe-php ^15, darkaonline/l5-swagger ^8.6,
PHP 8.3, MySQL 8.0. Si al construir la imagen Composer resuelve versiones ligeramente distintas
por actualizaciones posteriores del ecosistema, no debería romper nada porque todas usan
Semantic Versioning con `^`.
