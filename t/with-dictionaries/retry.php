<?php
function my_headers($ok, $code, $delay) {
    if ($ok) {
        header('HTTP/1.1 200 OK');
        header('Content-Type: text/plain');
        header('ETag: ABC');
    } else {
        if ($code == 503) {
            header('HTTP/1.1 503 Service Temporarily Unavailable');
        } elseif ($code == 429) {
            header('HTTP/1.1 429 Too Many Requests');
        }
        header("Retry-After: $delay");
    }
}

function age($time) {
    touch('/tmp/now');
    clearstatcache();
    $now = filemtime('/tmp/now');
    return $now - $time;
}
function request() {
    if (preg_match('{(\d+)}', $_SERVER['REQUEST_URI'], $matches)) {
        $code = $matches[1];
    } else {
        $code = $_ENV['CODE'];
    }
    $d = getenv('DELAY') ?: 2;
    $c = "/tmp/canary.$code";
    if (file_exists($c)) {
        clearstatcache();
        $last=filemtime($c);
        $last_age=age($last);
        if ($last_age > $d) {
            my_headers(1, $code, $d);
            if ($code == 503) {
                echo("blippy\n");
            } elseif ($code == 429) {
                echo("bloppy\n");
            }
        } else {
            my_headers(0, $code, $d);
            echo "error\n";
        }
    } else {
        my_headers(0, $code, $d);
        echo "not ready for $code\n";
        touch($c);
    }
}
request();
?>
