<?php

namespace App\Services;

use App\Models\Contract;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class ContractPdfService
{
    /** Ancho (en puntos PDF) con que se dibuja la firma. */
    private const SIG_DISPLAY_WIDTH = 180;

    /** Posición X de la firma (a la derecha del texto). */
    private const SIG_X = 350;

    /** Altura mínima disponible al pie de cada página. */
    private const PAGE_BOTTOM = 50;

    /**
     * Genera un PDF autónomo, sin depender de paquetes externos.
     * Las firmas manuales (PNG guardados en storage) se incrustan como
     * imágenes RGB comprimidas con Flate. Requiere la extensión GD.
     */
    public function generate(Contract $contract): string
    {
        $directory = 'contracts';
        Storage::disk('local')->makeDirectory($directory);

        $path = $directory . '/contrato-' . $contract->id . '.pdf';
        $absolute = Storage::disk('local')->path($path);

        $signatures = [
            'admin' => $this->loadSignature($contract->admin_signature_path ?? null),
            'super' => $this->loadSignature($contract->super_signature_path ?? null),
        ];

        $pages = $this->buildPages($contract, $signatures);
        $pdf = $this->buildPdf($pages, $signatures);

        file_put_contents($absolute, $pdf);

        return $path;
    }

    /**
     * Lee el PNG de la firma y lo convierte a RGB crudo comprimido (zlib),
     * que es lo que PDF espera con /FlateDecode + /DeviceRGB.
     */
    private function loadSignature(?string $path): ?array
    {
        if (!$path) {
            return null;
        }

        if (!Storage::disk('local')->exists($path)) {
            Log::warning('Firma no encontrada en storage: ' . $path);
            return null;
        }

        if (!function_exists('imagecreatefromstring')) {
            Log::warning('La extension GD de PHP no esta activa: no se puede incrustar la firma en el PDF.');
            return null;
        }

        $src = @imagecreatefromstring(Storage::disk('local')->get($path));
        if (!$src) {
            Log::warning('No se pudo leer la imagen de la firma: ' . $path);
            return null;
        }

        $sw = imagesx($src);
        $sh = imagesy($src);
        if ($sw < 1 || $sh < 1) {
            return null;
        }

        $w = min(300, $sw);
        $h = max(1, (int) round($sh * $w / $sw));

        // Lienzo blanco para eliminar cualquier transparencia.
        $dst = imagecreatetruecolor($w, $h);
        $white = imagecolorallocate($dst, 255, 255, 255);
        imagefill($dst, 0, 0, $white);
        imagecopyresampled($dst, $src, 0, 0, 0, 0, $w, $h, $sw, $sh);

        $rgb = '';
        for ($y = 0; $y < $h; $y++) {
            for ($x = 0; $x < $w; $x++) {
                $c = imagecolorat($dst, $x, $y);
                $rgb .= chr(($c >> 16) & 255)
                      . chr(($c >> 8) & 255)
                      . chr($c & 255);
            }
        }

        return [
            'w' => $w,
            'h' => $h,
            'data' => gzcompress($rgb),
        ];
    }

    private function sigDisplayHeight(array $sig): float
    {
        return self::SIG_DISPLAY_WIDTH * $sig['h'] / $sig['w'];
    }

    /** Altura total que ocupa un item dentro de la página. */
    private function itemHeight(array $item, array $signatures): float
    {
        if ($item['type'] === 'text') {
            return 15;
        }

        $textHeight = count($item['lines']) * 15;
        $sig = $item['key'] ? ($signatures[$item['key']] ?? null) : null;

        if (!$sig) {
            return $textHeight;
        }

        return max($textHeight, $this->sigDisplayHeight($sig) + 14);
    }

    private function buildPages(Contract $contract, array $signatures): array
    {
        $lines = [];

        $lines[] = 'CONVENIO COMERCIAL - CUPON APP';
        $lines[] = 'Contrato: ' . $contract->contract_number;
        $lines[] = 'Fecha de generacion: ' . optional($contract->created_at)->format('d/m/Y H:i');
        $lines[] = '';
        $lines[] = 'PARTES';
        $lines[] = 'CUPON APP, en adelante "LA PLATAFORMA", y el negocio identificado';
        $lines[] = 'en este convenio como "EL NEGOCIO", acuerdan sujetarse a las';
        $lines[] = 'siguientes condiciones comerciales y operativas.';
        $lines[] = '';
        $lines[] = '1. DATOS DEL NEGOCIO';
        $lines[] = 'Nombre: ' . ($contract->business_name ?: 'No proporcionado');
        $lines[] = 'Representante/contacto: ' . ($contract->contact_name ?: 'No proporcionado');
        $lines[] = 'Correo: ' . ($contract->contact_email ?: 'No proporcionado');
        $lines[] = 'RFC: ' . ($contract->rfc ?: 'No proporcionado');
        $lines[] = 'Domicilio: ' . ($contract->address ?: 'No proporcionado');
        $lines[] = 'Telefono: ' . ($contract->phone ?: 'No proporcionado');
        if ($contract->description) {
            $lines[] = 'Descripcion: ' . $contract->description;
        }
        $lines[] = '';
        $lines[] = '2. OBJETO DEL CONVENIO';
        $lines[] = 'EL NEGOCIO autoriza la publicacion y operacion de promociones y';
        $lines[] = 'cupones dentro de CUPON APP, de acuerdo con los datos, condiciones';
        $lines[] = 'y vigencias que sean registradas en la plataforma.';
        $lines[] = '';
        $lines[] = '3. COMISIONES Y OBLIGACIONES DE PAGO';
        $lines[] = 'Las partes reconocen las siguientes condiciones registradas para el';
        $lines[] = 'negocio al momento de generar este convenio:';
        $lines[] = 'Comision por producto: $' . number_format((float) $contract->commission_product, 2);
        $lines[] = 'Comision porcentual: ' . number_format((float) $contract->commission_percent, 2) . '%';
        $lines[] = 'Comision monetaria: $' . number_format((float) $contract->commission_money, 2);
        $lines[] = '';
        $lines[] = 'Cuando corresponda un canje o venta que genere una comision, EL NEGOCIO';
        $lines[] = 'se obliga a reconocer y cubrir la cantidad correspondiente conforme a';
        $lines[] = 'la modalidad aplicable y a los registros de CUPON APP.';
        $lines[] = 'Los importes, reportes y comprobantes podran ser consultados en los';
        $lines[] = 'mecanismos administrativos disponibles en la plataforma.';
        $lines[] = '';
        $lines[] = '4. REGISTRO Y VALIDACION DE CUPONES';
        $lines[] = 'EL NEGOCIO debera proporcionar informacion verdadera y vigente sobre';
        $lines[] = 'sus promociones, precios, restricciones, fechas y disponibilidad.';
        $lines[] = 'No debera publicar beneficios inexistentes, engañosos o que no pueda';
        $lines[] = 'cumplir frente al usuario que presente un cupon valido.';
        $lines[] = '';
        $lines[] = '5. CANJE Y ATENCION AL USUARIO';
        $lines[] = 'El personal autorizado por EL NEGOCIO debera validar el codigo, QR o';
        $lines[] = 'mecanismo de canje habilitado por CUPON APP antes de entregar el';
        $lines[] = 'beneficio. Cada canje debera respetar las condiciones publicadas.';
        $lines[] = '';
        $lines[] = '6. VIGENCIA, CAMBIOS Y BAJAS';
        $lines[] = 'Las promociones tendran la vigencia indicada en cada cupon. Los cambios';
        $lines[] = 'de condiciones deberan realizarse por los medios autorizados y no podran';
        $lines[] = 'afectar indebidamente a usuarios que ya hayan obtenido un beneficio valido.';
        $lines[] = '';
        $lines[] = '7. CONFIDENCIALIDAD Y DATOS';
        $lines[] = 'Las partes deberan manejar de forma responsable la informacion comercial';
        $lines[] = 'y los datos personales a los que tengan acceso con motivo de la operacion,';
        $lines[] = 'utilizandolos solamente para las finalidades permitidas por la normativa';
        $lines[] = 'aplicable y por las reglas de la plataforma.';
        $lines[] = '';
        $lines[] = '8. INCUMPLIMIENTO';
        $lines[] = 'El incumplimiento de las obligaciones de este convenio podra dar lugar a';
        $lines[] = 'la suspension de promociones, retencion o reclamacion de cantidades';
        $lines[] = 'que correspondan y, cuando proceda, al ejercicio de los derechos y';
        $lines[] = 'acciones previstos por la legislacion aplicable. Esto no constituye por si';
        $lines[] = 'mismo una declaracion de responsabilidad penal ni sustituye una resolucion';
        $lines[] = 'de la autoridad competente.';
        $lines[] = '';
        $lines[] = '9. ACEPTACION ELECTRONICA';
        $lines[] = 'La aceptacion realizada dentro de CUPON APP registra el usuario que';
        $lines[] = 'acepto, su nombre y correo, la fecha y hora, la direccion IP disponible';
        $lines[] = 'y la firma manual dibujada por el firmante.';
        $lines[] = 'Este mecanismo constituye una evidencia de aceptacion dentro de la';
        $lines[] = 'plataforma. Si las partes requieren una firma electronica avanzada o';
        $lines[] = 'certificada con efectos especificos, deberan utilizar el proveedor y';
        $lines[] = 'mecanismo que corresponda conforme a la legislacion aplicable.';
        $lines[] = '';
        $lines[] = '10. JURISDICCION Y LEGISLACION';
        $lines[] = 'Las partes procuraran resolver de buena fe cualquier diferencia derivada';
        $lines[] = 'del presente convenio. En lo no previsto, se atendera a la legislacion';
        $lines[] = 'aplicable y a las autoridades competentes.';
        $lines[] = '';
        $lines[] = 'FIRMAS / ACEPTACIONES';

        $items = [];

        foreach ($lines as $line) {
            foreach ($this->wrapLine($line, 88) as $wrappedLine) {
                $items[] = ['type' => 'text', 'text' => $wrappedLine];
            }
        }

        // ── Bloque del administrador: texto a la izquierda, firma a la derecha ──
        $items[] = $this->signerBlock(
            'admin',
            [
                'Administrador del negocio: ' . ($contract->admin_signed_name ?: 'Pendiente'),
                'Correo: ' . ($contract->admin_signed_email ?: 'Pendiente'),
                'Fecha: ' . ($contract->admin_signed_at ? $contract->admin_signed_at->format('d/m/Y H:i:s') : 'Pendiente'),
                'Firma manual:' . ($signatures['admin'] ? '' : ' Pendiente'),
            ],
            $signatures['admin']
        );

        $items[] = ['type' => 'text', 'text' => ''];

        // ── Bloque del súper administrador ──
        $items[] = $this->signerBlock(
            'super',
            [
                'Super administrador: ' . ($contract->super_signed_name ?: 'Pendiente'),
                'Correo: ' . ($contract->super_signed_email ?: 'Pendiente'),
                'Fecha: ' . ($contract->super_signed_at ? $contract->super_signed_at->format('d/m/Y H:i:s') : 'Pendiente'),
                'Firma manual:' . ($signatures['super'] ? '' : ' Pendiente'),
            ],
            $signatures['super']
        );

        $items[] = ['type' => 'text', 'text' => ''];
        foreach ($this->wrapLine('Documento generado por CUPON APP. Contrato ' . $contract->contract_number . '.', 88) as $l) {
            $items[] = ['type' => 'text', 'text' => $l];
        }

        // Paginación por altura.
        $pages = [];
        $current = [];
        $y = 760;

        foreach ($items as $item) {
            $height = $this->itemHeight($item, $signatures);

            if ($y - $height < self::PAGE_BOTTOM && !empty($current)) {
                $pages[] = $current;
                $current = [];
                $y = 760;
            }

            $current[] = $item;
            $y -= $height;
        }

        if (!empty($current)) {
            $pages[] = $current;
        }

        return $pages ?: [[['type' => 'text', 'text' => 'CONVENIO COMERCIAL - CUPON APP']]];
    }

    /**
     * Crea un bloque de firmante. Las líneas se parten a 40 caracteres
     * para no chocar con la firma, que va a la derecha.
     */
    private function signerBlock(string $key, array $rawLines, ?array $sig): array
    {
        $wrapped = [];
        foreach ($rawLines as $l) {
            $wrapped = array_merge($wrapped, $this->wrapLine($l, 40));
        }

        return [
            'type' => 'block',
            'lines' => $wrapped,
            'key' => $sig ? $key : null,
        ];
    }

    private function wrapLine(string $line, int $width): array
    {
        $line = trim($line);
        if ($line === '') return [''];

        $text = function_exists('iconv')
            ? iconv('UTF-8', 'Windows-1252//TRANSLIT//IGNORE', $line)
            : $line;

        $words = preg_split('/\s+/', $text ?: '');
        $result = [];
        $current = '';

        foreach ($words as $word) {
            if ($current === '') {
                $current = $word;
                continue;
            }

            if (strlen($current) + 1 + strlen($word) <= $width) {
                $current .= ' ' . $word;
            } else {
                $result[] = $current;
                $current = $word;
            }
        }

        if ($current !== '') $result[] = $current;

        return $result ?: [''];
    }

    private function buildPdf(array $pages, array $signatures): string
    {
        $objects = [];
        $objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
        $objects[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';

        $next = 4;

        // Objetos de imagen (una por firma disponible).
        $imageObjects = [];
        $imageNames = ['admin' => 'ImAdmin', 'super' => 'ImSuper'];

        foreach ($signatures as $key => $sig) {
            if (!$sig) continue;

            $objNum = $next++;
            $imageObjects[$key] = $objNum;
            $objects[$objNum] =
                '<< /Type /XObject /Subtype /Image'
                . ' /Width ' . $sig['w']
                . ' /Height ' . $sig['h']
                . ' /ColorSpace /DeviceRGB /BitsPerComponent 8'
                . ' /Filter /FlateDecode /Length ' . strlen($sig['data']) . " >>\nstream\n"
                . $sig['data']
                . "\nendstream";
        }

        $xobjectDict = '';
        if (!empty($imageObjects)) {
            $entries = [];
            foreach ($imageObjects as $key => $objNum) {
                $entries[] = '/' . $imageNames[$key] . ' ' . $objNum . ' 0 R';
            }
            $xobjectDict = ' /XObject << ' . implode(' ', $entries) . ' >>';
        }

        $pageObjectNumbers = [];

        foreach ($pages as $page) {
            $pageObj = $next++;
            $contentObj = $next++;
            $pageObjectNumbers[] = $pageObj;

            $commands = [];
            $y = 760;

            foreach ($page as $item) {
                if ($item['type'] === 'text') {
                    $safe = $this->escapePdfText($item['text']);
                    $commands[] = 'BT /F1 11 Tf 1 0 0 1 50 ' . $y . ' Tm (' . $safe . ') Tj ET';
                    $y -= 15;
                    continue;
                }

                // Bloque de firmante: texto a la izquierda...
                $top = $y;
                $lineY = $top;
                foreach ($item['lines'] as $textLine) {
                    $safe = $this->escapePdfText($textLine);
                    $commands[] = 'BT /F1 11 Tf 1 0 0 1 50 ' . $lineY . ' Tm (' . $safe . ') Tj ET';
                    $lineY -= 15;
                }

                // ...y la firma a la derecha, con una línea debajo.
                if ($item['key'] && isset($signatures[$item['key']])) {
                    $sig = $signatures[$item['key']];
                    $dw = self::SIG_DISPLAY_WIDTH;
                    $dh = $this->sigDisplayHeight($sig);
                    $bottom = $top + 10 - $dh;

                    $commands[] = sprintf(
                        'q %.2F 0 0 %.2F %d %.2F cm /%s Do Q',
                        $dw,
                        $dh,
                        self::SIG_X,
                        $bottom,
                        $imageNames[$item['key']]
                    );
                    $commands[] = sprintf(
                        '0.5 w %d %.2F m %d %.2F l S',
                        self::SIG_X,
                        $bottom - 2,
                        self::SIG_X + $dw,
                        $bottom - 2
                    );
                }

                $y -= $this->itemHeight($item, $signatures);
            }

            $content = implode("\n", $commands);

            $objects[$contentObj] = '<< /Length ' . strlen($content) . " >>\nstream\n" . $content . "\nendstream";
            $objects[$pageObj] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792]'
                . ' /Resources << /Font << /F1 3 0 R >>' . $xobjectDict . ' >>'
                . ' /Contents ' . $contentObj . ' 0 R >>';
        }

        $kids = implode(' ', array_map(fn ($n) => $n . ' 0 R', $pageObjectNumbers));
        $objects[2] = '<< /Type /Pages /Kids [' . $kids . '] /Count ' . count($pageObjectNumbers) . ' >>';

        ksort($objects);

        $pdf = "%PDF-1.4\n%\xE2\xE3\xCF\xD3\n";
        $offsets = [0 => 0];
        $maxObject = max(array_keys($objects));

        for ($i = 1; $i <= $maxObject; $i++) {
            if (!isset($objects[$i])) continue;
            $offsets[$i] = strlen($pdf);
            $pdf .= $i . " 0 obj\n" . $objects[$i] . "\nendobj\n";
        }

        $xref = strlen($pdf);
        $pdf .= "xref\n0 " . ($maxObject + 1) . "\n";
        $pdf .= "0000000000 65535 f \n";

        for ($i = 1; $i <= $maxObject; $i++) {
            $pdf .= sprintf("%010d 00000 n \n", $offsets[$i] ?? 0);
        }

        $pdf .= "trailer\n<< /Size " . ($maxObject + 1) . " /Root 1 0 R >>\n";
        $pdf .= "startxref\n" . $xref . "\n%%EOF";

        return $pdf;
    }

    private function escapePdfText(string $text): string
    {
        return str_replace(
            ['\\', '(', ')', "\r", "\n"],
            ['\\\\', '\\(', '\\)', '', ''],
            $text
        );
    }
}