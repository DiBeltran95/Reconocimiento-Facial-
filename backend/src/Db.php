<?php
declare(strict_types=1);

namespace App;

use PDO;
use PDOStatement;

final class Db
{
    private static ?PDO $pdo = null;

    public static function pdo(): PDO
    {
        if (self::$pdo === null) {
            $dsn = sprintf(
                'mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4',
                Config::get('db.host'),
                (int) Config::get('db.port', 3306),
                Config::get('db.name'),
            );
            self::$pdo = new PDO($dsn, Config::get('db.user'), Config::get('db.pass'), [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
                PDO::ATTR_STRINGIFY_FETCHES  => false,
            ]);
            // Todo el sistema guarda UTC; la sesión también trabaja en UTC.
            self::$pdo->exec("SET time_zone = '+00:00'");
        }
        return self::$pdo;
    }

    public static function query(string $sql, array $params = []): PDOStatement
    {
        $stmt = self::pdo()->prepare($sql);
        $stmt->execute($params);
        return $stmt;
    }

    public static function fila(string $sql, array $params = []): ?array
    {
        $fila = self::query($sql, $params)->fetch();
        return $fila === false ? null : $fila;
    }

    public static function filas(string $sql, array $params = []): array
    {
        return self::query($sql, $params)->fetchAll();
    }

    public static function valor(string $sql, array $params = []): mixed
    {
        $valor = self::query($sql, $params)->fetchColumn();
        return $valor === false ? null : $valor;
    }

    /** Placeholders `?,?,?` para un IN (...). */
    public static function enLista(array $valores): string
    {
        return implode(',', array_fill(0, max(1, count($valores)), '?'));
    }
}
