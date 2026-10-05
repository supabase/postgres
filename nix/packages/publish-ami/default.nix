{
  awscli2,
  coldsnap,
  qemu,
  writeShellApplication,
}:
writeShellApplication {
  name = "publish-ami";

  runtimeInputs = [
    awscli2
    coldsnap
    qemu
  ];

  text = builtins.readFile ./publish-ami.sh;
}
