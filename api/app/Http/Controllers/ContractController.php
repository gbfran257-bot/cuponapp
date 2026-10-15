<?php

namespace App\Http\Controllers;

use App\Models\Business;
use App\Models\Contract;
use App\Services\ContractPdfService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\Str;

class ContractController extends Controller
{
    public function index(Request $request)
    {
        $user = $request->user();

        $this->ensureAllowed($user);

        $query = Contract::with([
            'business',
            'admin',
        ])->orderByDesc('id');

        /*
         * El administrador solamente puede ver
         * los contratos de los negocios que tiene asignados.
         *
         * El súper administrador puede ver TODOS
         * los contratos.
         */
        if ($user->role === 'administrador') {
            $query->where(
                'admin_id',
                $user->id
            );
        }

        return response()->json(
            $query
                ->get()
                ->map(
                    fn (Contract $contract) =>
                        $this->format($contract)
                )
                ->values()
        );
    }

    public function show(
        Request $request,
        string $id
    ) {
        $user = $request->user();

        $this->ensureAllowed($user);

        $contract = Contract::with([
            'business',
            'admin',
        ])->findOrFail($id);

        $this->ensureCanView(
            $contract,
            $user
        );

        $this->ensurePdf($contract);

        return response()->json(
            $this->format(
                $contract->fresh([
                    'business',
                    'admin',
                ])
            )
        );
    }

    public function accept(
        Request $request,
        string $id,
        ContractPdfService $pdfService
    ) {
        $user = $request->user();

        $this->ensureAllowed($user);

        $contract = Contract::with([
            'business',
            'admin',
        ])->findOrFail($id);

        $this->ensureCanView(
            $contract,
            $user
        );

        /*
         * La firma manual (PNG en base64) es obligatoria.
         */
        $request->validate([
            'signature' => ['required', 'string'],
        ], [
            'signature.required' =>
                'Debes dibujar tu firma para aceptar el contrato.',
        ]);

        /*
         * FIRMA DEL ADMINISTRADOR
         */
        if ($user->role === 'administrador') {

            if ($contract->status === 'accepted') {
                return response()->json([
                    'message' =>
                        'El contrato ya fue aceptado por ambas partes.',
                    'contract' =>
                        $this->format($contract),
                ]);
            }

            if ($contract->admin_signed_at) {
                return response()->json([
                    'message' =>
                        'El administrador ya aceptó este contrato.',
                    'contract' =>
                        $this->format($contract),
                ], 422);
            }

            $contract->admin_signature_path =
                $this->storeSignature(
                    $request,
                    $contract,
                    'admin'
                );

            $contract->admin_signed_by =
                $user->id;

            $contract->admin_signed_name =
                $user->name;

            $contract->admin_signed_email =
                $user->email;

            $contract->admin_signed_at =
                now();

            $contract->admin_signed_ip =
                $request->ip();

            /*
             * IMPORTANTE:
             *
             * Después de que el administrador firma,
             * el contrato queda pendiente del
             * súper administrador.
             */
            $contract->status =
                'pending_super_admin';

            $contract->save();
        }

        /*
         * FIRMA DEL SÚPER ADMINISTRADOR
         */
        else {

            if ($contract->status === 'accepted') {
                return response()->json([
                    'message' =>
                        'El contrato ya fue aceptado por ambas partes.',
                    'contract' =>
                        $this->format($contract),
                ]);
            }

            /*
             * El súper administrador NO puede firmar
             * antes de que firme el administrador.
             */
            if (!$contract->admin_signed_at) {
                return response()->json([
                    'message' =>
                        'Primero debe aceptar el administrador del negocio.',
                ], 422);
            }

            if ($contract->super_signed_at) {
                return response()->json([
                    'message' =>
                        'El súper administrador ya aceptó este contrato.',
                    'contract' =>
                        $this->format($contract),
                ], 422);
            }

            $contract->super_signature_path =
                $this->storeSignature(
                    $request,
                    $contract,
                    'super'
                );

            $contract->super_signed_by =
                $user->id;

            $contract->super_signed_name =
                $user->name;

            $contract->super_signed_email =
                $user->email;

            $contract->super_signed_at =
                now();

            $contract->super_signed_ip =
                $request->ip();

            /*
             * Cuando ambos firman:
             * contrato completamente aceptado.
             */
            $contract->status =
                'accepted';

            $contract->save();
        }

        /*
         * Regeneramos el PDF después de registrar
         * la aceptación para que el documento
         * conserve las firmas/fechas registradas.
         */
        $pdfService->generate(
            $contract->fresh()
        );

        return response()->json([
            'message' =>
                'Aceptación electrónica registrada correctamente.',

            'contract' =>
                $this->format(
                    $contract->fresh([
                        'business',
                        'admin',
                    ])
                ),
        ]);
    }

        public function pdf(
        Request $request,
        string $id,
        ContractPdfService $pdfService
    ) {
        $contract = Contract::findOrFail($id);

        // Se regenera siempre para reflejar las firmas más recientes.
        $path = $pdfService->generate($contract);

        if ($contract->pdf_path !== $path) {
            $contract->pdf_path = $path;
            $contract->save();
        }

        return response()->file(
            Storage::disk('local')->path($path),
            [
                'Content-Type' => 'application/pdf',
                'Content-Disposition' =>
                    'inline; filename="' . $contract->contract_number . '.pdf"',
            ]
        );
    }

    /**
     * Se utiliza al crear un negocio desde
     * BusinessController.
     *
     * No modifica negocios existentes.
     * Solamente crea el primer convenio
     * del negocio nuevo.
     */
    public function createForBusiness(
        Business $business,
        ContractPdfService $pdfService
    ): Contract {
        if (!$business->admin_id) {
            throw new \RuntimeException(
                'El negocio necesita un administrador asignado para generar el contrato.'
            );
        }

        $contract = Contract::create([
            'business_id' =>
                $business->id,

            'admin_id' =>
                $business->admin_id,

            'contract_number' =>
                $this->nextContractNumber(),

            'status' =>
                'pending_admin',

            'business_name' =>
                $business->name,

            'contact_name' =>
                $business->contact_name,

            'contact_email' =>
                $business->contact_email,

            'rfc' =>
                $business->rfc,

            'address' =>
                $business->address,

            'phone' =>
                $business->phone,

            'commission_product' =>
                $business->commission_product,

            'commission_percent' =>
                $business->commission_percent,

            'commission_money' =>
                $business->commission_money,

            'description' =>
                $business->description,
        ]);

        $path = $pdfService->generate(
            $contract
        );

        $contract->pdf_path =
            $path;

        $contract->document_hash =
            hash_file(
                'sha256',
                Storage::disk('local')->path($path)
            );

        $contract->save();

        return $contract->fresh([
            'business',
            'admin',
        ]);
    }

    /**
     * Valida y guarda la firma manual (PNG en base64)
     * y devuelve la ruta relativa en el disco "local".
     */
    private function storeSignature(
        Request $request,
        Contract $contract,
        string $who
    ): string {
        $raw = (string) $request->input('signature');

        // Acepta tanto base64 puro como "data:image/png;base64,...".
        $raw = preg_replace('/^data:image\/\w+;base64,/', '', $raw);

        $binary = base64_decode($raw, true);

        $isPng =
            $binary !== false &&
            strlen($binary) >= 100 &&
            strlen($binary) <= 2 * 1024 * 1024 &&
            substr($binary, 0, 8) === "\x89PNG\r\n\x1a\n";

        if (!$isPng) {
            abort(
                422,
                'La firma manual no es válida. Dibuja tu firma e inténtalo de nuevo.'
            );
        }

        $directory = 'contracts/signatures';
        Storage::disk('local')->makeDirectory($directory);

        $path = $directory .
            '/contrato-' . $contract->id .
            '-' . $who . '.png';

        Storage::disk('local')->put($path, $binary);

        return $path;
    }

    private function nextContractNumber(): string
    {
        do {
            $number =
                'CUP-' .
                now()->format('Ymd') .
                '-' .
                strtoupper(
                    Str::random(6)
                );
        } while (
            Contract::where(
                'contract_number',
                $number
            )->exists()
        );

        return $number;
    }

    private function ensurePdf(
        Contract $contract,
        ?ContractPdfService $pdfService = null
    ): string {
        if (
            $contract->pdf_path &&
            Storage::disk('local')->exists(
                $contract->pdf_path
            )
        ) {
            return $contract->pdf_path;
        }

        $pdfService ??=
            app(ContractPdfService::class);

        $path =
            $pdfService->generate(
                $contract
            );

        $contract->pdf_path =
            $path;

        $contract->document_hash =
            hash_file(
                'sha256',
                Storage::disk('local')->path($path)
            );

        $contract->save();

        return $path;
    }

    private function ensureAllowed($user): void
    {
    abort_unless($user, 401, 'Usuario no autenticado.');

    $role = strtolower(trim((string) $user->role));

    // Normalizamos espacios y guiones para aceptar las variantes
    // que pueda tener guardado el rol en la base de datos.
    $normalizedRole = str_replace(
        [' ', '-'],
        '_',
        $role
    );

    if ($normalizedRole === 'administrador') {
        return;
    }

    if (in_array($normalizedRole, [
        'super_admin',
        'superadmin',
        'super_administrador',
        'superadministrador',
    ], true)) {
        return;
    }

    abort(
        403,
        'No tienes permiso para consultar contratos.'
    );
    }

    private function ensureCanView(
        Contract $contract,
        $user
    ): void {
        /*
         * El administrador únicamente puede
         * consultar contratos que le pertenecen.
         *
         * El súper administrador puede consultar
         * cualquier contrato.
         */
        if (
            $user->role ===
            'administrador'
        ) {
            abort_unless(
                (int) $contract->admin_id ===
                    (int) $user->id,
                403,
                'Este contrato no pertenece a tu negocio.'
            );
        }
    }

    private function format(
        Contract $contract
    ): array {
        return [
            'id' =>
                (string) $contract->id,

            'businessId' =>
                (string) $contract->business_id,

            'businessName' =>
                $contract->business_name,

            'adminId' =>
                $contract->admin_id
                    ? (string) $contract->admin_id
                    : null,

            'adminName' =>
                $contract->admin?->name,

            'adminEmail' =>
                $contract->admin?->email,

            'contractNumber' =>
                $contract->contract_number,

            'status' =>
                $contract->status,

            'statusLabel' =>
                match ($contract->status) {

                    'pending_admin' =>
                        'Pendiente de firma del administrador',

                    'pending_super_admin' =>
                        'Pendiente de firma del súper administrador',

                    'accepted' =>
                        'Aceptado por ambas partes',

                    default =>
                        $contract->status,
                },

            'contactName' =>
                $contract->contact_name,

            'contactEmail' =>
                $contract->contact_email,

            'rfc' =>
                $contract->rfc,

            'address' =>
                $contract->address,

            'phone' =>
                $contract->phone,

            'commissionProduct' =>
                (float) $contract->commission_product,

            'commissionPercent' =>
                (float) $contract->commission_percent,

            'commissionMoney' =>
                (float) $contract->commission_money,

            'description' =>
                $contract->description,

            'pdfUrl' =>
                URL::temporarySignedRoute(
                    'contracts.pdf',
                    now()->addMinutes(30),
                    [
                        'id' =>
                            $contract->id,
                    ]
                ),

            'documentHash' =>
                $contract->document_hash,

            'adminSigned' =>
                (bool) $contract->admin_signed_at,

            'adminSignedName' =>
                $contract->admin_signed_name,

            'adminSignedEmail' =>
                $contract->admin_signed_email,

            'adminSignedAt' =>
                $contract->admin_signed_at
                    ?->toIso8601String(),

            'superSigned' =>
                (bool) $contract->super_signed_at,

            'superSignedName' =>
                $contract->super_signed_name,

            'superSignedEmail' =>
                $contract->super_signed_email,

            'superSignedAt' =>
                $contract->super_signed_at
                    ?->toIso8601String(),

            'createdAt' =>
                $contract->created_at
                    ?->toIso8601String(),
        ];
    }
}