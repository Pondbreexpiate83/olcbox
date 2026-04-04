package org.turnbox.app.macos

import org.turnbox.app.data.datasource.DEFAULT_MACOS_APP_GROUP_ID
import org.turnbox.app.data.datasource.HysteriaConfigRepositoryImpl
import org.turnbox.app.data.datasource.MacosHysteriaConfigDataSource

class MacosDependencies(
    appGroupId: String = DEFAULT_MACOS_APP_GROUP_ID
) {
    private val dataSource = MacosHysteriaConfigDataSource(appGroupId)

    val appGroupIdentifier: String = appGroupId
    val sharedDirectoryPath: String = dataSource.sharedDirectoryPath
    val masterConfigPath: String = dataSource.masterConfigPath
    val repository = HysteriaConfigRepositoryImpl(dataSource)
    val configStore = MacosConfigStore(repository)
}
