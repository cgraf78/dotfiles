<?php

// Standalone PHP fallback for hooks outside a project. Repo-local
// .php-cs-fixer.php/.php-cs-fixer.dist.php files always take precedence.
return (new PhpCsFixer\Config())
    ->setRiskyAllowed(false)
    ->setRules([
        '@PSR12' => true,
        'array_syntax' => ['syntax' => 'short'],
    ]);
