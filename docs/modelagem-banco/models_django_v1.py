"""
Sistema de Gestão de Vendas e Caixa — Elgin M10 Pro
Modelagem em Django ORM (v1.1) — corresponde a `modelo_de_dados_v1.md`.

Decisões da v1.1:
  - catálogo e cliente com escopo POR LOJA (FK composta garante coerência no banco);
  - caixa com abertura/fechamento (CashSession) e sangria/suprimento (CashMovement).

Organização sugerida em apps:
    accounts/      -> User, Role, Permission, UserRole, UserStore
    stores/        -> Store, Terminal, TerminalSeller, DeviceSession
    catalog/       -> ProductCategory, Product
    customers/     -> Customer
    sales/         -> Sale, SaleItem, PrintedDocument, SaleChangeRequest,
                      SaleCancellation, SaleReturn, SaleReturnItem
    cash/          -> CashSession, CashMovement, Payment
    receivables/   -> Receivable, ReceivablePayment
    commissions/   -> CommissionRule, CommissionItem, CommissionAdjustment
    sync/          -> SyncOperation, SyncConflict, IdempotencyKey
    audit/         -> AuditLog

Este arquivo reúne tudo para leitura; na implementação, quebrar por app.
"""

import uuid

from django.conf import settings
from django.contrib.auth.models import AbstractUser
from django.contrib.postgres.constraints import ExclusionConstraint
from django.contrib.postgres.fields import DateTimeRangeField, RangeOperators
from django.db import models
from django.db.models import Q, F
from django.db.models.functions import Func


# ---------------------------------------------------------------------------
# Bases e enums compartilhados
# ---------------------------------------------------------------------------

MONEY = dict(max_digits=12, decimal_places=2)
QTY = dict(max_digits=12, decimal_places=3)
PERCENT = dict(max_digits=5, decimal_places=2)


class PaymentMethod(models.TextChoices):
    PIX = "PIX"
    DINHEIRO = "DINHEIRO"
    CREDITO = "CREDITO"
    DEBITO = "DEBITO"
    NOTINHA = "NOTINHA"


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class OfflineOriginModel(TimeStampedModel):
    """Entidade que pode nascer no terminal, sem internet (RF33–RF37)."""

    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    occurred_at = models.DateTimeField(
        help_text="Data/hora do evento no terminal (X-Client-Timestamp). Não é a hora do envio."
    )
    created_offline = models.BooleanField(default=False)

    class Meta:
        abstract = True


# ---------------------------------------------------------------------------
# 1. Identidade e organização
# ---------------------------------------------------------------------------

class Store(TimeStampedModel):
    code = models.CharField(max_length=10, unique=True)      # L1, L2
    name = models.CharField(max_length=120)
    document = models.CharField(max_length=18, blank=True)
    address = models.CharField(max_length=255, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "store"


class Role(models.Model):
    class Code(models.TextChoices):
        DONO = "DONO"
        GERENTE = "GERENTE"
        VENDEDOR = "VENDEDOR"
        CAIXA = "CAIXA"

    code = models.CharField(max_length=12, choices=Code.choices, unique=True)
    name = models.CharField(max_length=60)
    description = models.TextField(blank=True)

    class Meta:
        db_table = "role"


class Permission(models.Model):
    code = models.CharField(max_length=60, unique=True)   # ex.: "sale.cancel"
    description = models.CharField(max_length=200)
    roles = models.ManyToManyField(Role, through="RolePermission", related_name="permissions")

    class Meta:
        db_table = "permission"


class RolePermission(models.Model):
    role = models.ForeignKey(Role, on_delete=models.CASCADE)
    permission = models.ForeignKey(Permission, on_delete=models.CASCADE)

    class Meta:
        db_table = "role_permission"
        constraints = [models.UniqueConstraint(fields=["role", "permission"], name="uq_role_permission")]


class User(AbstractUser):
    """
    Vendedor pode não ter senha: no M10 ele apenas é selecionado (sem credencial).
    Dono, Gerente e Caixa autenticam por usuário/senha.
    """
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=20, blank=True)
    roles = models.ManyToManyField(Role, through="UserRole", related_name="users")
    stores = models.ManyToManyField(Store, through="UserStore", related_name="users")

    class Meta:
        db_table = "user"

    def has_role(self, code: str) -> bool:
        return self.roles.filter(code=code).exists()


class UserRole(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    role = models.ForeignKey(Role, on_delete=models.PROTECT)
    granted_by = models.ForeignKey(User, null=True, on_delete=models.SET_NULL, related_name="granted_roles")
    granted_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "user_role"
        constraints = [models.UniqueConstraint(fields=["user", "role"], name="uq_user_role")]


class UserStore(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    is_default = models.BooleanField(default=False)

    class Meta:
        db_table = "user_store"
        constraints = [models.UniqueConstraint(fields=["user", "store"], name="uq_user_store")]


class Terminal(TimeStampedModel):
    """A senha pertence ao terminal, não ao vendedor."""

    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name="terminals")
    device_identifier = models.CharField(max_length=64, unique=True)  # X-Device-Id
    name = models.CharField(max_length=80)
    password = models.CharField(max_length=128)      # hash (make_password)
    model = models.CharField(max_length=40, blank=True, default="46PGM1021600")
    android_version = models.CharField(max_length=20, blank=True, default="11")
    is_active = models.BooleanField(default=True)
    last_seen_at = models.DateTimeField(null=True, blank=True)
    sellers = models.ManyToManyField(User, through="TerminalSeller", related_name="terminals")

    class Meta:
        db_table = "terminal"


class TerminalSeller(models.Model):
    terminal = models.ForeignKey(Terminal, on_delete=models.CASCADE)
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "terminal_seller"
        constraints = [models.UniqueConstraint(fields=["terminal", "user"], name="uq_terminal_seller")]


class DeviceSession(models.Model):
    class Kind(models.TextChoices):
        TERMINAL = "TERMINAL"
        SESSION = "SESSION"

    terminal = models.ForeignKey(Terminal, on_delete=models.CASCADE, related_name="sessions")
    seller = models.ForeignKey(User, null=True, blank=True, on_delete=models.SET_NULL)
    kind = models.CharField(max_length=12, choices=Kind.choices)
    token_jti = models.CharField(max_length=64, unique=True)
    issued_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)

    class Meta:
        db_table = "device_session"
        indexes = [models.Index(fields=["terminal", "expires_at"])]


# ---------------------------------------------------------------------------
# 2. Catálogo
# ---------------------------------------------------------------------------

class ProductCategory(models.Model):
    code = models.CharField(max_length=30, unique=True)      # PECAS, PNEUS, OLEOS
    name = models.CharField(max_length=60)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "product_category"


class Product(TimeStampedModel):
    """
    Sem controle de estoque: identificação, preço e categoria.
    Catálogo POR LOJA — as duas lojas vendem produtos diferentes.
    """

    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name="products")
    sku = models.CharField(max_length=40)
    barcode = models.CharField(max_length=64, null=True, blank=True)
    name = models.CharField(max_length=160)
    category = models.ForeignKey(ProductCategory, on_delete=models.PROTECT, related_name="products")
    price = models.DecimalField(**MONEY)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "product"
        indexes = [models.Index(fields=["store", "category", "is_active"])]
        constraints = [
            models.CheckConstraint(check=Q(price__gte=0), name="ck_product_price_positive"),
            models.UniqueConstraint(fields=["store", "sku"], name="uq_product_store_sku"),
            models.UniqueConstraint(
                fields=["store", "barcode"], condition=Q(barcode__isnull=False),
                name="uq_product_store_barcode",
            ),
            # Chave alternativa para a FK composta de SaleItem (produto da loja da venda).
            models.UniqueConstraint(fields=["id", "store"], name="uq_product_id_store"),
        ]


class Customer(OfflineOriginModel):
    """Cliente PERTENCE A UMA LOJA — cadastros e pendências não cruzam lojas."""

    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name="customers")
    name = models.CharField(max_length=160)
    document = models.CharField(max_length=18, null=True, blank=True)   # único por loja
    phone = models.CharField(max_length=20, blank=True)
    address = models.CharField(max_length=255, blank=True)
    notes = models.TextField(blank=True)
    created_by = models.ForeignKey(User, on_delete=models.PROTECT, related_name="customers_created")
    version = models.IntegerField(default=1)
    is_active = models.BooleanField(default=True)

    class Meta:
        db_table = "customer"
        indexes = [
            models.Index(fields=["store", "is_active"]),
            models.Index(fields=["name"]),
        ]
        constraints = [
            models.UniqueConstraint(
                fields=["store", "document"], condition=Q(document__isnull=False),
                name="uq_customer_store_document",
            ),
            # Chave alternativa para a FK composta de Sale e Receivable.
            models.UniqueConstraint(fields=["id", "store"], name="uq_customer_id_store"),
        ]


# ---------------------------------------------------------------------------
# 3. Venda
# ---------------------------------------------------------------------------

class Sale(OfflineOriginModel):
    class Status(models.TextChoices):
        AGUARDANDO_CAIXA = "AGUARDANDO_CAIXA"
        PAGA = "PAGA"
        EM_ALTERACAO = "EM_ALTERACAO"
        CANCELADA = "CANCELADA"
        DEVOLVIDA_PARCIAL = "DEVOLVIDA_PARCIAL"
        DEVOLVIDA_TOTAL = "DEVOLVIDA_TOTAL"

    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name="sales")
    terminal = models.ForeignKey(Terminal, on_delete=models.PROTECT, related_name="sales")
    seller = models.ForeignKey(User, on_delete=models.PROTECT, related_name="sales")   # RF06: um só
    customer = models.ForeignKey(Customer, null=True, blank=True, on_delete=models.PROTECT, related_name="sales")

    status = models.CharField(max_length=24, choices=Status.choices, default=Status.AGUARDANDO_CAIXA)
    payment_method = models.CharField(max_length=12, choices=PaymentMethod.choices)
    barcode = models.CharField(max_length=40, unique=True)

    gross_amount = models.DecimalField(**MONEY)
    discount_amount = models.DecimalField(default=0, **MONEY)
    total_amount = models.DecimalField(**MONEY)   # valor efetivamente vendido (13.3)

    sync_operation = models.ForeignKey(
        "SyncOperation", null=True, blank=True, on_delete=models.SET_NULL, related_name="sales"
    )
    version = models.IntegerField(default=1)

    class Meta:
        db_table = "sale"
        indexes = [
            models.Index(fields=["store", "status", "-occurred_at"]),
            models.Index(fields=["seller", "-occurred_at"]),
            models.Index(fields=["customer"]),
        ]
        constraints = [
            models.CheckConstraint(
                check=~Q(payment_method=PaymentMethod.NOTINHA) | Q(customer__isnull=False),
                name="ck_sale_notinha_requires_customer",   # RF14
            ),
            models.CheckConstraint(check=Q(total_amount__gte=0), name="ck_sale_total_positive"),
        ]


class SaleItem(models.Model):
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="items")
    store = models.ForeignKey(Store, on_delete=models.PROTECT)   # sustenta a FK composta com Product
    product = models.ForeignKey(Product, on_delete=models.PROTECT, related_name="sale_items")

    # snapshots — o item é a fonte de verdade histórica
    product_name = models.CharField(max_length=160)
    category = models.ForeignKey(ProductCategory, on_delete=models.PROTECT)

    quantity = models.DecimalField(**QTY)
    unit_price = models.DecimalField(**MONEY)
    discount = models.DecimalField(default=0, **MONEY)
    line_total = models.DecimalField(**MONEY)
    returned_quantity = models.DecimalField(default=0, **QTY)

    class Meta:
        db_table = "sale_item"
        indexes = [models.Index(fields=["sale"]), models.Index(fields=["product"])]
        constraints = [
            models.CheckConstraint(check=Q(quantity__gt=0), name="ck_sale_item_qty_positive"),
            models.CheckConstraint(
                check=Q(returned_quantity__lte=F("quantity")), name="ck_sale_item_returned_lte_qty"
            ),
        ]


class PrintedDocument(models.Model):
    class DocType(models.TextChoices):
        DOC1 = "DOC1", "Encaminhamento ao caixa"
        DOC2 = "DOC2", "Retirada da compra"

    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="documents")
    doc_type = models.CharField(max_length=6, choices=DocType.choices)
    reference = models.CharField(max_length=40, unique=True)   # DOC2-10482-9K1
    barcode = models.CharField(max_length=40, blank=True)
    sequence = models.PositiveIntegerField(default=1)          # reimpressões
    printed_by = models.ForeignKey(User, on_delete=models.PROTECT)
    terminal = models.ForeignKey(Terminal, on_delete=models.PROTECT)
    printed_at = models.DateTimeField()

    class Meta:
        db_table = "printed_document"
        indexes = [models.Index(fields=["sale", "doc_type"])]


class SaleChangeRequest(TimeStampedModel):
    class Status(models.TextChoices):
        PENDENTE = "PENDENTE"
        APROVADA = "APROVADA"
        REJEITADA = "REJEITADA"

    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="change_requests")
    requested_by = models.ForeignKey(User, on_delete=models.PROTECT, related_name="change_requests")
    requested_changes = models.JSONField()      # schema definitivo em aberto
    reason = models.TextField()
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.PENDENTE)
    decided_by = models.ForeignKey(User, null=True, blank=True, on_delete=models.PROTECT, related_name="change_decisions")
    decision_note = models.TextField(blank=True)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "sale_change_request"
        indexes = [models.Index(fields=["sale", "status"])]


class SaleCancellation(models.Model):
    sale = models.OneToOneField(Sale, on_delete=models.PROTECT, related_name="cancellation")
    reason = models.TextField()                                  # obrigatório (RF26)
    cancelled_by = models.ForeignKey(User, on_delete=models.PROTECT)   # dono/gerente
    cancelled_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "sale_cancellation"


class SaleReturn(TimeStampedModel):
    class ReturnType(models.TextChoices):
        TOTAL = "TOTAL"
        PARCIAL = "PARCIAL"

    uuid = models.UUIDField(default=uuid.uuid4, unique=True, editable=False)
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="returns")
    return_type = models.CharField(max_length=8, choices=ReturnType.choices)
    document2 = models.ForeignKey(
        PrintedDocument, on_delete=models.PROTECT, to_field="reference",
        db_column="document2_reference", related_name="returns",
        help_text="Documento 2 obrigatório (13.4) — sem ele, 422.",
    )
    reason = models.TextField()
    total_amount = models.DecimalField(**MONEY)
    authorized_by = models.ForeignKey(User, on_delete=models.PROTECT)   # dono/gerente

    class Meta:
        db_table = "sale_return"
        indexes = [models.Index(fields=["sale"])]


class SaleReturnItem(models.Model):
    sale_return = models.ForeignKey(SaleReturn, on_delete=models.PROTECT, related_name="items")
    sale_item = models.ForeignKey(SaleItem, on_delete=models.PROTECT, related_name="return_items")
    quantity = models.DecimalField(**QTY)
    amount = models.DecimalField(**MONEY)

    class Meta:
        db_table = "sale_return_item"
        constraints = [
            models.UniqueConstraint(fields=["sale_return", "sale_item"], name="uq_return_item"),
            models.CheckConstraint(check=Q(quantity__gt=0), name="ck_return_item_qty_positive"),
        ]


# ---------------------------------------------------------------------------
# 4. Caixa
# ---------------------------------------------------------------------------

class CashSession(OfflineOriginModel):
    """
    Sessão de caixa: abertura, movimentos e fechamento com conferência.
    Pode ser aberta e fechada offline — o caixa não pode parar sem internet.
    Apenas DINHEIRO é conferido fisicamente; as demais formas saem em relatório.
    """

    class Status(models.TextChoices):
        ABERTA = "ABERTA"
        FECHADA = "FECHADA"

    store = models.ForeignKey(Store, on_delete=models.PROTECT, related_name="cash_sessions")
    terminal = models.ForeignKey(Terminal, on_delete=models.PROTECT, related_name="cash_sessions")
    cashier = models.ForeignKey(User, on_delete=models.PROTECT, related_name="cash_sessions")
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ABERTA)

    opening_amount = models.DecimalField(**MONEY)          # fundo de troco
    opened_at = models.DateTimeField()
    closed_at = models.DateTimeField(null=True, blank=True)
    closed_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.PROTECT, related_name="cash_sessions_closed"
    )
    expected_cash_amount = models.DecimalField(null=True, blank=True, **MONEY)
    counted_cash_amount = models.DecimalField(null=True, blank=True, **MONEY)
    # difference: coluna GENERATED (counted - expected) criada via RunSQL
    closing_note = models.TextField(blank=True)

    class Meta:
        db_table = "cash_session"
        indexes = [models.Index(fields=["store", "-opened_at"])]
        constraints = [
            models.UniqueConstraint(
                fields=["terminal"], condition=Q(status="ABERTA"),
                name="uq_cash_session_open_terminal",   # uma sessão aberta por terminal
            ),
            models.CheckConstraint(check=Q(opening_amount__gte=0), name="ck_cash_opening_positive"),
        ]


class CashMovement(OfflineOriginModel):
    """Sangria e suprimento — entram no cálculo do esperado em dinheiro."""

    class MovementType(models.TextChoices):
        SUPRIMENTO = "SUPRIMENTO"
        SANGRIA = "SANGRIA"
        AJUSTE = "AJUSTE"

    cash_session = models.ForeignKey(CashSession, on_delete=models.PROTECT, related_name="movements")
    movement_type = models.CharField(max_length=12, choices=MovementType.choices)
    amount = models.DecimalField(**MONEY)
    reason = models.TextField()
    created_by = models.ForeignKey(User, on_delete=models.PROTECT, related_name="cash_movements")
    authorized_by = models.ForeignKey(
        User, null=True, blank=True, on_delete=models.PROTECT, related_name="cash_movements_authorized"
    )

    class Meta:
        db_table = "cash_movement"
        indexes = [models.Index(fields=["cash_session", "occurred_at"])]
        constraints = [models.CheckConstraint(check=Q(amount__gt=0), name="ck_cash_movement_positive")]


class Payment(OfflineOriginModel):
    """Um pagamento por venda — sem pagamento dividido (13.7)."""

    sale = models.OneToOneField(Sale, on_delete=models.PROTECT, related_name="payment")
    cash_session = models.ForeignKey(CashSession, on_delete=models.PROTECT, related_name="payments")
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    terminal = models.ForeignKey(Terminal, on_delete=models.PROTECT)
    cashier = models.ForeignKey(User, on_delete=models.PROTECT, related_name="payments_received")
    payment_method = models.CharField(max_length=12, choices=PaymentMethod.choices)
    amount = models.DecimalField(**MONEY)

    class Meta:
        db_table = "payment"
        indexes = [
            models.Index(fields=["store", "-occurred_at"]),
            models.Index(fields=["cash_session", "payment_method"]),
        ]
        constraints = [
            models.CheckConstraint(
                check=~Q(payment_method=PaymentMethod.NOTINHA),
                name="ck_payment_not_notinha",   # notinha vai para receivable_payment
            )
        ]


# ---------------------------------------------------------------------------
# 5. Notinha e pendências
# ---------------------------------------------------------------------------

class Receivable(OfflineOriginModel):
    class Status(models.TextChoices):
        ABERTA = "ABERTA"
        EM_RECEBIMENTO = "EM_RECEBIMENTO"
        EM_ALTERACAO = "EM_ALTERACAO"
        QUITADA = "QUITADA"
        CANCELADA = "CANCELADA"
        BAIXADA_DEVOLUCAO = "BAIXADA_DEVOLUCAO"
        VENCIDA = "VENCIDA"          # reservado (13.8)

    sale = models.OneToOneField(Sale, on_delete=models.PROTECT, related_name="receivable")
    customer = models.ForeignKey(Customer, on_delete=models.PROTECT, related_name="receivables")
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    original_amount = models.DecimalField(**MONEY)
    paid_amount = models.DecimalField(default=0, **MONEY)
    # pending_amount: coluna GENERATED criada via RunSQL na migração
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ABERTA)
    due_date = models.DateField(null=True, blank=True)
    version = models.IntegerField(default=1)

    class Meta:
        db_table = "receivable"
        indexes = [
            models.Index(fields=["customer", "status"]),
            models.Index(fields=["store", "status"]),
        ]


class ReceivablePayment(OfflineOriginModel):
    """Quitação integral em uma única operação (13.1)."""

    receivable = models.ForeignKey(Receivable, on_delete=models.PROTECT, related_name="payments")
    cash_session = models.ForeignKey(CashSession, on_delete=models.PROTECT, related_name="receivable_payments")
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    terminal = models.ForeignKey(Terminal, null=True, blank=True, on_delete=models.PROTECT)
    cashier = models.ForeignKey(User, on_delete=models.PROTECT, related_name="receivable_payments")
    payment_method = models.CharField(max_length=12, choices=PaymentMethod.choices)
    amount = models.DecimalField(**MONEY)
    voided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "receivable_payment"
        constraints = [
            models.UniqueConstraint(
                fields=["receivable"], condition=Q(voided_at__isnull=True),
                name="uq_receivable_payment_effective",
            ),
            models.CheckConstraint(
                check=~Q(payment_method=PaymentMethod.NOTINHA), name="ck_receivable_payment_not_notinha"
            ),
        ]


# ---------------------------------------------------------------------------
# 6. Comissão — acesso exclusivo do Dono (RF18, RNF03)
# ---------------------------------------------------------------------------

class CommissionRule(models.Model):
    """Append-only: alterar percentual cria nova linha e fecha a vigência anterior."""

    seller = models.ForeignKey(User, on_delete=models.PROTECT, related_name="commission_rules")
    category = models.ForeignKey(ProductCategory, on_delete=models.PROTECT, related_name="commission_rules")
    percent = models.DecimalField(**PERCENT)
    effective_from = models.DateTimeField()
    effective_to = models.DateTimeField(null=True, blank=True)
    created_by = models.ForeignKey(User, on_delete=models.PROTECT, related_name="commission_rules_created")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "commission_rule"
        indexes = [models.Index(fields=["seller", "category", "-effective_from"])]
        constraints = [
            models.CheckConstraint(
                check=Q(percent__gte=0) & Q(percent__lte=100), name="ck_commission_percent_range"
            ),
            # Vigências não podem se sobrepor (requer btree_gist).
            ExclusionConstraint(
                name="ex_commission_rule_no_overlap",
                expressions=[
                    ("seller", RangeOperators.EQUAL),
                    ("category", RangeOperators.EQUAL),
                    (
                        Func(
                            F("effective_from"), F("effective_to"), models.Value("[)"),
                            function="tstzrange", output_field=DateTimeRangeField(),
                        ),
                        RangeOperators.OVERLAPS,
                    ),
                ],
            ),
        ]


class CommissionItem(models.Model):
    """Percentual e valor congelados no item da venda (RF20)."""

    class Status(models.TextChoices):
        CALCULADA = "CALCULADA"
        RETIDA = "RETIDA"
        LIBERADA = "LIBERADA"
        ESTORNADA = "ESTORNADA"
        AJUSTADA = "AJUSTADA"

    sale_item = models.OneToOneField(SaleItem, on_delete=models.PROTECT, related_name="commission")
    sale = models.ForeignKey(Sale, on_delete=models.PROTECT, related_name="commissions")
    seller = models.ForeignKey(User, on_delete=models.PROTECT, related_name="commissions")
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    category = models.ForeignKey(ProductCategory, on_delete=models.PROTECT)
    commission_rule = models.ForeignKey(
        CommissionRule, null=True, blank=True, on_delete=models.SET_NULL, related_name="items"
    )

    base_amount = models.DecimalField(**MONEY)      # valor líquido do item
    percent = models.DecimalField(**PERCENT)        # snapshot
    amount = models.DecimalField(**MONEY)           # valor corrente após ajustes
    status = models.CharField(max_length=12, choices=Status.choices, default=Status.CALCULADA)
    calculated_at = models.DateTimeField(auto_now_add=True)
    released_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "commission_item"
        indexes = [
            models.Index(fields=["seller", "category", "calculated_at"]),
            models.Index(fields=["sale"]),
            models.Index(fields=["status"]),
        ]


class CommissionAdjustment(models.Model):
    """Ajuste/estorno nunca apaga o registro anterior (RF28, RF31)."""

    class Origin(models.TextChoices):
        CANCELAMENTO = "CANCELAMENTO"
        DEVOLUCAO = "DEVOLUCAO"
        MANUAL = "MANUAL"

    commission_item = models.ForeignKey(CommissionItem, on_delete=models.PROTECT, related_name="adjustments")
    previous_amount = models.DecimalField(**MONEY)
    new_amount = models.DecimalField(**MONEY)
    origin = models.CharField(max_length=16, choices=Origin.choices)
    reason = models.TextField()
    adjusted_by = models.ForeignKey(User, on_delete=models.PROTECT)     # Dono
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = "commission_adjustment"
        indexes = [models.Index(fields=["commission_item", "created_at"])]


# ---------------------------------------------------------------------------
# 7. Sincronização
# ---------------------------------------------------------------------------

class SyncOperation(models.Model):
    class OpType(models.TextChoices):
        SALE_CREATE = "SALE_CREATE"
        CASH_PAYMENT = "CASH_PAYMENT"
        CUSTOMER_CREATE = "CUSTOMER_CREATE"
        RECEIVABLE_PAYMENT = "RECEIVABLE_PAYMENT"
        DOCUMENT_PRINT = "DOCUMENT_PRINT"
        CASH_SESSION_OPEN = "CASH_SESSION_OPEN"
        CASH_SESSION_CLOSE = "CASH_SESSION_CLOSE"
        CASH_MOVEMENT = "CASH_MOVEMENT"
        AUDIT_BATCH = "AUDIT_BATCH"

    class Status(models.TextChoices):
        PENDENTE_SINCRONIZACAO = "PENDENTE_SINCRONIZACAO"
        SINCRONIZADO = "SINCRONIZADO"
        ERRO_SINCRONIZACAO = "ERRO_SINCRONIZACAO"
        CONFLITANTE = "CONFLITANTE"

    operation_id = models.UUIDField(unique=True)          # deduplicação (RF36)
    terminal = models.ForeignKey(Terminal, on_delete=models.PROTECT, related_name="sync_operations")
    store = models.ForeignKey(Store, on_delete=models.PROTECT)
    user = models.ForeignKey(User, on_delete=models.PROTECT, related_name="sync_operations")
    op_type = models.CharField(max_length=24, choices=OpType.choices)
    payload = models.JSONField()
    status = models.CharField(max_length=28, choices=Status.choices)
    entity_type = models.CharField(max_length=40, blank=True)
    entity_id = models.BigIntegerField(null=True, blank=True)     # server_id devolvido
    error_code = models.CharField(max_length=40, blank=True)
    error_message = models.TextField(blank=True)
    attempts = models.PositiveIntegerField(default=0)
    occurred_at = models.DateTimeField()          # hora do evento, não do envio (RF37)
    received_at = models.DateTimeField(auto_now_add=True)
    processed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "sync_operation"
        indexes = [
            models.Index(fields=["terminal", "status", "occurred_at"]),
            models.Index(fields=["op_type", "status"]),
        ]


class SyncConflict(models.Model):
    class Status(models.TextChoices):
        PENDENTE = "PENDENTE"
        RESOLVIDO = "RESOLVIDO"

    class Resolution(models.TextChoices):
        MANTER_SERVIDOR = "MANTER_SERVIDOR"
        APLICAR_OPERACAO_LOCAL = "APLICAR_OPERACAO_LOCAL"
        MESCLAR = "MESCLAR"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    sync_operation = models.ForeignKey(SyncOperation, on_delete=models.PROTECT, related_name="conflicts")
    entity_type = models.CharField(max_length=40)
    entity_id = models.BigIntegerField(null=True, blank=True)
    server_state = models.JSONField()
    local_state = models.JSONField()
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDENTE)
    resolution = models.CharField(max_length=24, choices=Resolution.choices, blank=True)
    note = models.TextField(blank=True)
    resolved_by = models.ForeignKey(User, null=True, blank=True, on_delete=models.PROTECT)  # gerente/dono
    created_at = models.DateTimeField(auto_now_add=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = "sync_conflict"
        indexes = [models.Index(fields=["status", "created_at"])]


class IdempotencyKey(models.Model):
    """Par (chave, resposta) retido por 24h (RF36, RNF04)."""

    key = models.UUIDField(primary_key=True)
    scope = models.CharField(max_length=80)        # endpoint
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    terminal = models.ForeignKey(Terminal, null=True, blank=True, on_delete=models.CASCADE)
    request_hash = models.CharField(max_length=64)
    response_status = models.PositiveSmallIntegerField()
    response_body = models.JSONField()
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()

    class Meta:
        db_table = "idempotency_key"
        indexes = [models.Index(fields=["expires_at"])]


# ---------------------------------------------------------------------------
# 8. Auditoria — imutável (RF29–RF32)
# ---------------------------------------------------------------------------

class AuditLog(models.Model):
    class Origin(models.TextChoices):
        ONLINE = "ONLINE"
        OFFLINE = "OFFLINE"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    occurred_at = models.DateTimeField()                       # hora do evento (preserva offline)
    recorded_at = models.DateTimeField(auto_now_add=True)      # hora da gravação no servidor
    user = models.ForeignKey(User, null=True, blank=True, on_delete=models.PROTECT, related_name="audit_logs")
    role = models.CharField(max_length=12)                     # snapshot do perfil
    store = models.ForeignKey(Store, null=True, blank=True, on_delete=models.PROTECT)
    terminal = models.ForeignKey(Terminal, null=True, blank=True, on_delete=models.PROTECT)
    action = models.CharField(max_length=40)
    entity = models.CharField(max_length=40)
    entity_id = models.CharField(max_length=40)
    before = models.JSONField(null=True, blank=True)
    after = models.JSONField(null=True, blank=True)
    reason = models.TextField(blank=True)
    ip = models.GenericIPAddressField(null=True, blank=True)
    operation_id = models.UUIDField(null=True, blank=True)
    origin = models.CharField(max_length=8, choices=Origin.choices, default=Origin.ONLINE)
    is_commission_related = models.BooleanField(default=False)  # oculta do Gerente (RF18)

    class Meta:
        db_table = "audit_log"
        indexes = [
            models.Index(fields=["entity", "entity_id"]),
            models.Index(fields=["store", "-occurred_at"]),
            models.Index(fields=["user", "-occurred_at"]),
            models.Index(fields=["action"]),
            models.Index(fields=["is_commission_related"]),
        ]

    def save(self, *args, **kwargs):
        if self.pk and AuditLog.objects.filter(pk=self.pk).exists():
            raise PermissionError("audit_log é imutável (RF31)")
        return super().save(*args, **kwargs)

    def delete(self, *args, **kwargs):
        raise PermissionError("audit_log não pode ser apagado (RF31)")


# ---------------------------------------------------------------------------
# Migrações complementares (RunSQL) — ver §5 do modelo_de_dados_v1.md
# ---------------------------------------------------------------------------
#  1. CREATE EXTENSION btree_gist;            -> ExclusionConstraint de commission_rule
#  2. CREATE EXTENSION pg_trgm;               -> busca por nome de produto/cliente
#  3. ALTER TABLE receivable ADD COLUMN pending_amount ... GENERATED ALWAYS AS ... STORED;
#  4. ALTER TABLE cash_session ADD COLUMN difference ... GENERATED ALWAYS AS
#         (counted_cash_amount - expected_cash_amount) STORED;
#  5. Trigger fn_audit_immutable() + REVOKE UPDATE, DELETE ON audit_log;
#  6. Trigger que impede PrintedDocument DOC2 quando sale.status <> 'PAGA';
#  7. FKs COMPOSTAS (o Django não as gera — usar RunSQL):
#         sale (customer_id, store_id)      -> customer (id, store_id)
#         sale_item (product_id, store_id)  -> product  (id, store_id)
#         receivable (customer_id, store_id)-> customer (id, store_id)
#  8. Trigger que exige cash_session ABERTA, do mesmo store_id e cashier_id,
#     ao inserir payment ou receivable_payment.
