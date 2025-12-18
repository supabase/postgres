let sp = builtins.getFlake "/home/leonardo/sp/postgres"; in
sp.outputs.packages.x86_64-linux."psql_17/bin"
