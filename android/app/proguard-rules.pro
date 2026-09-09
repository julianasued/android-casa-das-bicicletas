# SDK E1 da Elgin.
#
# As classes são resolvidas por nome em dois pontos: pela própria E1, que
# escolhe a implementação do periférico conforme o modelo do aparelho, e pelo
# canal legado do aplicativo, que chama a impressora por reflexão. Ofuscar
# qualquer um dos dois quebra a impressora apenas em release.
-keep class com.elgin.e1.** { *; }
-keep class com.elgin.minipdvm8.** { *; }
-dontwarn com.elgin.e1.**

# Serviço nativo do terminal (impressora e display fazem bind por AIDL).
-keep class net.nyx.** { *; }
-dontwarn net.nyx.**
