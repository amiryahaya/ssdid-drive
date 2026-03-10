FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy project files and restore
COPY src/SsdidDrive.Api/SsdidDrive.Api.csproj src/SsdidDrive.Api/
RUN dotnet restore src/SsdidDrive.Api/SsdidDrive.Api.csproj

# Copy source and publish
COPY src/ src/
RUN dotnet publish src/SsdidDrive.Api/SsdidDrive.Api.csproj -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

# Create directories for data and logs
RUN mkdir -p /app/data /app/logs

COPY --from=build /app/publish .

# Copy native KAZ-Sign library if present
COPY src/SsdidDrive.Api/runtimes/ runtimes/

ENV ASPNETCORE_URLS=http://+:8080
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ENABLE_AUTO_MIGRATE=true

EXPOSE 8080

ENTRYPOINT ["dotnet", "SsdidDrive.Api.dll"]
