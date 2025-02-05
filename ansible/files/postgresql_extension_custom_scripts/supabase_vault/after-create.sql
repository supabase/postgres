grant usage on schema vault to postgres with grant option;
grant select, delete on vault.secrets, vault.decrypted_secrets to postgres with grant option;
grant execute on function vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt to postgres with grant option;
