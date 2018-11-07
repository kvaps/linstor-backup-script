#!/bin/bash
set -eo pipefail
VERSION=0.3.0

cat <<EOT
# Linstor configuration file
# Generated by: $(basename $0) ($VERSION)
# Date:         $(date)
# Controller:   $(linstor controller version)
# Client:       $(linstor --version 2>&1)
EOT

echo
echo "# Controller Options"
linstor -m controller list-properties | jq -jr '.[][] | .key, " ", .value, "\n"' |
  while read key value; do
    echo "linstor controller set-property $key $value"
  done

echo
echo "# Nodes"
linstor -m node list | jq -jr '.[] | select(.nodes) | .nodes[] | .name, " ", ( .net_interfaces[] | select(.name == "default") |.address ), "\n"' |
  while read name ip; do
    echo "linstor node create $name $ip"
    linstor -m node list-properties $name | jq -jr '.[][] | .key, " ", .value, "\n"' |
      while read key value; do
        echo "  linstor node set-property $name $key $value"
      done
  done

echo
echo "# Node Interfaces"
linstor -m node list | jq -jrc '.[] | select(.nodes) | .nodes[] | .name, " ", (.net_interfaces[] | select(.name != "default") | [ .name, .address ] ), "\n"' |
  while read node_name net_interfaces; do
    echo $net_interfaces | jq -r '.[]' | paste - - |
      while read interface_name ip; do
        echo "linstor node interface create $node_name $interface_name $ip"
      done
  done

echo
echo "# Storage Pool Definitions"
linstor -m storage-pool-definition list | jq -r '.[] | select(.stor_pool_dfns) | .stor_pool_dfns[] | .stor_pool_name' |
  while read name; do
    echo "linstor storage-pool-definition create $name"
    linstor -m storage-pool-definition list-properties $name | jq -jr '.[][] | .key, " ", .value, "\n"' |
      while read key value; do
        echo "  linstor storage-pool-definition set-property $name $key $value"
      done
  done

storage_pool_properties() {
  linstor -m storage-pool list-properties $node_name $name | jq -jr '.[][] | .key, " ", .value, "\n"' |
    while read key value; do
      echo "  linstor storage-pool set-property $node_name $name $key $value"
    done
}

echo
echo "# Storage Pools (lvm)"
linstor -m storage-pool list | jq -jr '.[] | select(.stor_pools) | .stor_pools[] | select(.driver == "LvmDriver") | .stor_pool_name, " ", .node_name, " ", (.props[] | select(.key == "StorDriver/LvmVg").value), "\n"' |
  while read name node_name driver_pool_name; do
    echo "linstor storage-pool create lvm $node_name $name $driver_pool_name"
    storage_pool_properties
  done

echo
echo "# Storage Pools (lvm-thin)"
linstor -m storage-pool list | jq -jr '.[] | select(.stor_pools) | .stor_pools[] | select(.driver == "LvmThinDriver") | .stor_pool_name, " ", .node_name, " ", (.props[] | select(.key == "StorDriver/LvmVg").value), " ", (.props[] | select(.key == "StorDriver/ThinPool").value), "\n"' |
  while read name node_name vg pool; do
    echo "linstor storage-pool create lvmthin $node_name $name $vg/$pool"
    storage_pool_properties
  done

echo
echo "# Storage Pools (zfs)"
linstor -m storage-pool list | jq -jr '.[] | select(.stor_pools) | .stor_pools[] | select(.driver == "ZfsDriver") | .stor_pool_name, " ", .node_name, " ", (.props[] | select(.key == "StorDriver/ZPool").value), "\n"' |
  while read name node_name driver_pool_name; do
    echo "linstor storage-pool create zfs $node_name $name $driver_pool_name"
    storage_pool_properties
  done

echo
echo "# Storage Pools (zfsthin)"
linstor -m storage-pool list | jq -jr '.[] | select(.stor_pools) | .stor_pools[] | select(.driver == "ZfsThinDriver") | .stor_pool_name, " ", .node_name, " ", (.props[] | select(.key == "StorDriver/ZPoolThin").value), "\n"' |
  while read name node_name driver_pool_name; do
    echo "linstor storage-pool create zfsthin $node_name $name $driver_pool_name"
    storage_pool_properties
  done

echo
echo "# Storage Pools (diskless)"
linstor -m sp l | jq -jr '.[] | select(.stor_pools) | .stor_pools[] | select(.driver == "DisklessDriver") | .stor_pool_name, " ", .node_name, "\n"' |
  while read name node_name vg pool; do
    echo "linstor storage-pool create diskless $node_name $name"
    storage_pool_properties
  done

echo
echo "# Resource Definitions"
linstor -m resource-definition list | jq -jr '.[] | select(.rsc_dfns) | .rsc_dfns[] | .rsc_name, " ", .rsc_dfn_port, "\n"' |
  while read rsc_name rsc_dfn_port; do
    echo "linstor resource-definition create -p $rsc_dfn_port $rsc_name"
    linstor -m resource-definition list-properties $rsc_name | jq -jr '.[][] | .key, " ", .value, "\n"' |
      while read key value; do
        echo "  linstor resource-definition set-property $rsc_name $key $value"
      done
  done

echo
echo "# Volume Definitions"
linstor -m volume-definition list | jq -jrc '.[] | select(.rsc_dfns) | .rsc_dfns[] | .rsc_name, " ", (.vlm_dfns | select(.) |.[] | [ .vlm_nr, .vlm_minor, .vlm_size ] ), "\n"' |
  while read rsc_name vlm_dfns; do
    echo "$vlm_dfns" | jq -r '.[]' | paste - - - |
      while read vlmnr minor size; do
        echo "linstor volume-definition create -n $vlmnr -m $minor $rsc_name $size"
        linstor -m volume-definition list-properties $rsc_name $vlmnr | jq -jr '.[][] | .key, " ", .value, "\n"' |
          while read key value; do
            echo "  linstor volume-definition set-property $rsc_name $vlmnr $key $value"
          done
      done
  done

echo
echo "# Resources"
linstor -m resource list | jq -jr '.[] | select(.resources) | .resources[] | .name, " ", .node_name, " ", (.props[] | select(.key == "StorPoolName").value ), "\n"' |
  while read resource_definition_name node_name storage_pool; do
    echo "linstor resource create -s $storage_pool $node_name $resource_definition_name"
    linstor -m resource list-properties $node_name $resource_definition_name | jq -r '.[][] | .key, .value ' | paste - - |
      while read key value; do
        echo "  linstor resource set-property $node_name $resource_definition_name $key $value"
      done
  done
