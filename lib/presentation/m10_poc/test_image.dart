/// Imagem de teste embutida, para exercitar `ImprimeImagem` sem depender de
/// arquivo no aparelho.
///
/// PNG de 128x48 com moldura e um "X" — desenho escolhido por ser obvio no
/// papel: se sair torto, cortado ou invertido, da para ver de longe. Vai
/// embutida em base64 porque um asset exigiria entrada no `pubspec` e um
/// caminho, e o POC precisa funcionar em qualquer build.
library;

import 'dart:convert';
import 'dart:typed_data';

const String _testImageBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAIAAAAAwCAAAAAD8ny1iAAAA0klEQVR42u2YSxLAIAhDvf+l'
    '221Hi2BEXzsje5MgH5FSjn3NrsVmcO7SUPE8CTfcQ8tQsS2V8Opgy7VKg4H7RrQgFDaiwZIq'
    'oeuQzZGlwcHpESSEwkdw0KckhBzwsVUNwXMRYCEU8RNB1CEJQ4LjbkVRB69LvteSlDCDydUl'
    'kMo2L7vFalFKvJiPqg6WMdRoUHqfTZrm0hr9JMgfBbAhYJMQLkO2EbGtGH6M2OeYHUjgkYwd'
    'StmxHP6YsF8z9nMKf8/ZBQW7ooGXVOyaDl9UHkPtBjxbtxw5cUD+AAAAAElFTkSuQmCC';

/// Bytes PNG da imagem de teste.
Uint8List testImageBytes() => base64Decode(_testImageBase64);
