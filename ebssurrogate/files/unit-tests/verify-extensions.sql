BEGIN;
SELECT plan(3);
SELECT has_function(
    'install_available_extensions_and_test'
);
SELECT function_returns(
    'install_available_extensions_and_test',
    'boolean'
);
SELECT ok(install_available_extensions_and_test(),'extension test');
SELECT * FROM finish();
ROLLBACK;
