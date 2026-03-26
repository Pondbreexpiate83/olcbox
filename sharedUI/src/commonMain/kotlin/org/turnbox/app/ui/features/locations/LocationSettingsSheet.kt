package org.turnbox.app.ui.features.locations

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import org.turnbox.app.ui.components.PingButton
import org.turnbox.app.ui.features.home.HomeScreenViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LocationSettingsSheet(
    onDismiss: () -> Unit,
    viewModel: LocationViewModel,
    homeViewModel: HomeScreenViewModel
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    val closeSheet = {
        scope.launch {
            sheetState.hide()
            onDismiss()
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle() }
    ) {
        LocationSettingsContent(
            viewModel = viewModel,
            homeViewModel = homeViewModel,
            onDismiss = { closeSheet() }
        )
    }
}

@Composable
fun LocationSettingsContent(
    viewModel: LocationViewModel,
    homeViewModel: HomeScreenViewModel,
    onDismiss: () -> Unit
) {
    val config = viewModel.editingConfig
    val name = viewModel.editingName
    val isSaving = viewModel.isSaving

    val focusManager = LocalFocusManager.current
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .verticalScroll(scrollState)
            .padding(bottom = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Location Settings",
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onSurface,
            modifier = Modifier.padding(bottom = 24.dp)
        )

        OutlinedTextField(
            value = name,
            onValueChange = { viewModel.onNameChanged(it) },
            label = { Text("Name") },
            placeholder = { Text("Helsinki, FI") },
            enabled = !isSaving,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
            trailingIcon = {
                if (name.isNotEmpty() && !isSaving) {
                    IconButton(onClick = { viewModel.onNameChanged("") }) {
                        Icon(Icons.Default.Close, contentDescription = "Clear")
                    }
                }
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        OutlinedTextField(
            value = config.server,
            onValueChange = { viewModel.onServerChanged(it) },
            label = { Text("TURN Client Address") },
            placeholder = { Text("95.85.240.113:56000") },
            enabled = !isSaving,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
            modifier = Modifier.fillMaxWidth(),
            trailingIcon = {
                if (config.server.isNotEmpty() && !isSaving) {
                    IconButton(onClick = { viewModel.onServerChanged("") }) {
                        Icon(Icons.Default.Close, contentDescription = "Clear")
                    }
                }
            }
        )

        Spacer(modifier = Modifier.height(16.dp))

        Row(modifier = Modifier.fillMaxWidth()) {
            OutlinedTextField(
                value = config.sni,
                onValueChange = { viewModel.onSniChanged(it) },
                label = { Text("SNI") },
                placeholder = { Text("localhost") },
                modifier = Modifier.weight(1f),
                enabled = !isSaving,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                trailingIcon = {
                    if (config.sni.isNotEmpty() && !isSaving) {
                        IconButton(onClick = { viewModel.onSniChanged("") }) {
                            Icon(Icons.Default.Close, contentDescription = "Clear")
                        }
                    }
                }
            )

            Spacer(modifier = Modifier.width(16.dp))

            OutlinedTextField(
                value = config.password,
                onValueChange = { viewModel.onPasswordChanged(it) },
                label = { Text("Password") },
                maxLines = 1,
                enabled = !isSaving,
                visualTransformation = PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(
                    onDone = {
                        focusManager.clearFocus()
                    }
                ),
                modifier = Modifier.weight(1f),
                trailingIcon = {
                    if (config.password.isNotEmpty() && !isSaving) {
                        IconButton(onClick = { viewModel.onPasswordChanged("") }) {
                            Icon(Icons.Default.Close, contentDescription = "Clear")
                        }
                    }
                }
            )
        }

        Spacer(modifier = Modifier.height(24.dp))

        PingButton(
            homeViewModel = homeViewModel,
            configGetter = { viewModel.editingConfig }
        )

        Spacer(modifier = Modifier.height(32.dp))

        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedIconButton(
                onClick = {
                    viewModel.editingId?.let { viewModel.deleteLocation(it) { onDismiss() } }
                        ?: onDismiss()
                },
                modifier = Modifier.size(56.dp),
                enabled = !isSaving,
                shape = CircleShape,
                border = BorderStroke(
                    1.dp,
                    MaterialTheme.colorScheme.outlineVariant
                )
            ) {
                Icon(Icons.Outlined.Delete, contentDescription = "Delete")
            }

            Spacer(modifier = Modifier.width(16.dp))

            Button(
                onClick = {
                    viewModel.saveEditing { onDismiss() }
                },
                modifier = Modifier
                    .weight(1f)
                    .height(56.dp),
                enabled = !isSaving,
                shape = RoundedCornerShape(28.dp)
            ) {
                if (isSaving) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                } else {
                    Icon(Icons.Rounded.Check, contentDescription = null)
                    Spacer(Modifier.width(8.dp))
                    Text("Save Location Settings", fontSize = 16.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}
