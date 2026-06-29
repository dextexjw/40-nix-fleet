{
  hosts,
  members ? [
    "gateway-vm"
    "gateway2-vm"
  ],
  primary ? "gateway-vm",
  vip ? "10.2.20.102",
}:

let
  memberHosts = builtins.listToAttrs (
    map (name: {
      inherit name;
      value = hosts.${name};
    }) members
  );
in
{
  inherit
    members
    memberHosts
    primary
    vip
    ;

  addresses = map (name: hosts.${name}.ip) members;
  clientAddress = if vip == null then hosts.${primary}.ip else vip;
  primaryHost = hosts.${primary};
  secondaryMembers = builtins.filter (name: name != primary) members;
}
