<?php
declare(strict_types=1);

require_once __DIR__ . '/config.php';

csac_bootstrap();

$route = csac_unicsac_route();
if ($route === '') {
    response_json(['success' => false, 'message' => '缺少 route 参数'], 400);
}

$routes = csac_unicsac_routes();
if (!isset($routes[$route])) {
    response_json(['success' => false, 'message' => '无效的 route: ' . $route], 404);
}

call_user_func($routes[$route]);

function csac_unicsac_route(): string
{
    $route = csac_input_string('route');
    if ($route === '' && isset($_SERVER['PATH_INFO']) && is_string($_SERVER['PATH_INFO'])) {
        $route = ltrim($_SERVER['PATH_INFO'], '/');
    }
    if ($route === '') {
        $path = parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH) ?: '';
        $script = basename($_SERVER['SCRIPT_NAME'] ?? '');
        $needle = '/' . $script . '/';
        $pos = strpos($path, $needle);
        if ($pos !== false) {
            $route = substr($path, $pos + strlen($needle));
        }
    }

    $route = trim($route);
    if ($route === '') {
        return '';
    }

    $route = ltrim(str_replace('\\', '/', $route), '/');
    $route = preg_replace('/[?#].*$/', '', $route) ?? $route;
    return trim($route, '/');
}

function csac_unicsac_routes(): array
{
    return csac_routes();
}
