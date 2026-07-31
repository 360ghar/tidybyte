import SwiftUI

struct PhotoPermissionView: View {
    let permissionHandler: PhotoPermissionHandler

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                Text("Photo Library Access Required")
                    .font(.title2.bold())

                Text("TidyByte needs access to your photo library to help you organize and clean up your photos and videos.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // The permission gate (RootView.permissionGatedView) never presents
            // this view for .authorized / .limited — they render the content
            // directly — so only .notDetermined and .denied/.restricted reach
            // the switch (de-slop: the old .limited/.authorized branches were
            // unreachable).
            switch permissionHandler.permissionState {
            case .notDetermined:
                Button {
                    Task {
                        await permissionHandler.requestPermission()
                    }
                } label: {
                    Text("Grant Access")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)

            default:
                VStack(spacing: 12) {
                    Text("Access was denied. Please enable it in Settings to use TidyByte.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        permissionHandler.openSettings()
                    } label: {
                        Text("Open Settings")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
    }
}
