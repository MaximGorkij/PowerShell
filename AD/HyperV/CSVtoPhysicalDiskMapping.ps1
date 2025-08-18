Function Get-CSVtoPhysicalDiskMapping {
    param (
        [string]$clustername = "."
    )

    $clusterSharedVolume = Get-ClusterSharedVolume -Cluster $clusterName

    foreach ($volume in $clusterSharedVolume) {
        $volumeowner = $volume.OwnerNode.Name
        $csvVolume = $volume.SharedVolumeInfo.Partition.Name
        $cimSession = New-CimSession -ComputerName $volumeowner
        $volumeInfo = Get-Disk -CimSession $cimSession | Get-Partition | Select-Object DiskNumber, @{
                Name="Volume";Expression={Get-Volume -Partition $_ | Select-Object -ExpandProperty ObjectId}
        }

        $csvdisknumber = ($volumeinfo | Where-Object { $_.Volume -eq $csvVolume}).Disknumber
        $csvtophysicaldisk = New-Object -TypeName PSObject -Property @{
                "CSVName" = $volume.Name
                "CSVVolumePath" = $volume.SharedVolumeInfo.FriendlyVolumeName
                "CSVOwnerNode" = $volumeowner
                "CSVPhysicalDiskNumber" = $csvdisknumber
                "CSVPartitionNumber" = $volume.SharedVolumeInfo.PartitionNumber
                "Size (GB)" = [int]($volume.SharedVolumeInfo.Partition.Size/1GB)
                "FreeSpace (GB)" = [int]($volume.SharedVolumeInfo.Partition.Freespace/1GB)
        }

        $csvtophysicaldisk
    }
}

Get-CSVtoPhysicalDiskMapping