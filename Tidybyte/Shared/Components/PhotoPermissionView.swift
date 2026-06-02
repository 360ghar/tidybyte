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

            case .denied, .restricted:
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

            case .limited:
                VStack(spacing: 12) {
                    Text("Limited access granted. For the best experience, allow access to all photos in Settings.")
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

            case .authorized:
                EmptyView()
            }

            Spacer()
        }
    }
}
