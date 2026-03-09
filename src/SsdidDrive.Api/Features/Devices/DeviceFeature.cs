namespace SsdidDrive.Api.Features.Devices;

public static class DeviceFeature
{
    public static void MapDeviceFeature(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/devices").WithTags("Devices");

        EnrollDevice.Map(group);
        ListDevices.Map(group);
        GetCurrentDevice.Map(group);
        UpdateDevice.Map(group);
        RevokeDevice.Map(group);
    }
}
