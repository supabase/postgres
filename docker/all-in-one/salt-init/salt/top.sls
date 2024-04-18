# base is used to store this top file
# file_roots in the master.conf must match these environment
base:
  '*':
    - core
    - supervisor
    - gotrue
    - fail2ban
