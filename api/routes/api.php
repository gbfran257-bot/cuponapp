<?php

use App\Http\Controllers\AuthController;
use App\Http\Controllers\BusinessController;
use App\Http\Controllers\ContractController;
use App\Http\Controllers\CouponController;
use App\Http\Controllers\EarningsController;
use App\Http\Controllers\SuperAdminController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

// Públicas
Route::post('/register', [AuthController::class, 'register']);
Route::post('/login', [AuthController::class, 'login']);

// PDF de contrato mediante URL firmada temporalmente.
// No expone el token Sanctum en el navegador.
Route::get('/contracts/{id}/pdf', [ContractController::class, 'pdf'])
    ->middleware('signed')
    ->name('contracts.pdf');

// Requieren token (Authorization: Bearer <token>)
Route::middleware('auth:sanctum')->group(function () {
    Route::post('/logout', [AuthController::class, 'logout']);
    Route::get('/me', fn (Request $request) => $request->user());

    // Usuario final
    Route::get('/coupons', [CouponController::class, 'index']);
    Route::get('/coupons/mine', [CouponController::class, 'mine']);
    Route::post('/coupons/capture', [CouponController::class, 'capture']);
    Route::post('/coupons/redeem', [CouponController::class, 'redeem']);

    // Administrador
    Route::get('/admin/my-businesses', [BusinessController::class, 'mine']);
    Route::get('/admin/coupons', [CouponController::class, 'adminIndex']);
    Route::post('/admin/coupons', [CouponController::class, 'store']);
    Route::post('/admin/coupons/{id}', [CouponController::class, 'update']);
    Route::patch('/admin/coupons/{id}/status', [CouponController::class, 'toggleStatus']);
    Route::delete('/admin/coupons/{id}', [CouponController::class, 'destroy']);

    // Contratos / convenios
    // El controlador limita los resultados según el rol del usuario.
    Route::get('/contracts', [ContractController::class, 'index']);
    Route::get('/contracts/{id}', [ContractController::class, 'show']);
    Route::post('/contracts/{id}/accept', [ContractController::class, 'accept']);

    // Súper administrador
    Route::get('/super-admin/stats', [SuperAdminController::class, 'stats']);
    Route::get('/super-admin/earnings', [EarningsController::class, 'summary']);
    Route::get('/super-admin/redemptions', [EarningsController::class, 'redemptions']);
    Route::patch('/super-admin/redemptions/{id}/paid', [EarningsController::class, 'markPaid']);

    // Negocios (ahora los maneja BusinessController)
    Route::get('/super-admin/businesses', [BusinessController::class, 'index']);
    Route::post('/super-admin/businesses', [BusinessController::class, 'store']);
    Route::put('/super-admin/businesses/{id}', [BusinessController::class, 'update']);
    Route::patch('/super-admin/businesses/{id}/status', [BusinessController::class, 'toggleStatus']);
    Route::delete('/super-admin/businesses/{id}', [BusinessController::class, 'destroy']);

    Route::get('/super-admin/admins', [SuperAdminController::class, 'admins']);
    Route::post('/super-admin/admins', [SuperAdminController::class, 'storeAdmin']);
    Route::put('/super-admin/admins/{id}', [SuperAdminController::class, 'updateAdmin']);
    Route::patch('/super-admin/admins/{id}/status', [SuperAdminController::class, 'toggleAdminStatus']);
    Route::delete('/super-admin/admins/{id}', [SuperAdminController::class, 'destroyAdmin']);

    Route::get('/super-admin/users', [SuperAdminController::class, 'users']);
    Route::post('/super-admin/users', [SuperAdminController::class, 'storeUser']);
    Route::put('/super-admin/users/{id}', [SuperAdminController::class, 'updateUser']);
    Route::patch('/super-admin/users/{id}/status', [SuperAdminController::class, 'toggleUserStatus']);
    Route::delete('/super-admin/users/{id}', [SuperAdminController::class, 'destroyUser']);
});
