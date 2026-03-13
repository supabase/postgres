{
  ...
}:
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      genesis = {
        #this file is just a placeholder to bootstrap 
        #the system manager, it will be replaced by real configurations
        environment.etc."system-manager-genesis" = {
          text = "";
          user = "root";
          group = "root";
          mode = "0644";
        };
      };
    };
  };
}
