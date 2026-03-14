using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddExtensionServicesAndTenantRequests : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "extension_services",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    TenantId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    ServiceKey = table.Column<string>(type: "character varying(512)", maxLength: 512, nullable: false),
                    Permissions = table.Column<string>(type: "jsonb", nullable: false, defaultValueSql: "'{}'::jsonb"),
                    Enabled = table.Column<bool>(type: "boolean", nullable: false, defaultValue: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    LastUsedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_extension_services", x => x.Id);
                    table.ForeignKey(
                        name: "FK_extension_services_tenants_TenantId",
                        column: x => x.TenantId,
                        principalTable: "tenants",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "tenant_requests",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    OrganizationName = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    RequesterEmail = table.Column<string>(type: "character varying(160)", maxLength: 160, nullable: false),
                    RequesterAccountId = table.Column<Guid>(type: "uuid", nullable: true),
                    Reason = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    Status = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false, defaultValue: "pending"),
                    ReviewedBy = table.Column<Guid>(type: "uuid", nullable: true),
                    ReviewedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    RejectionReason = table.Column<string>(type: "character varying(1024)", maxLength: 1024, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_tenant_requests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_tenant_requests_users_RequesterAccountId",
                        column: x => x.RequesterAccountId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_tenant_requests_users_ReviewedBy",
                        column: x => x.ReviewedBy,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                });

            migrationBuilder.CreateIndex(
                name: "IX_extension_services_TenantId",
                table: "extension_services",
                column: "TenantId");

            migrationBuilder.CreateIndex(
                name: "IX_extension_services_TenantId_Name",
                table: "extension_services",
                columns: new[] { "TenantId", "Name" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_tenant_requests_RequesterAccountId",
                table: "tenant_requests",
                column: "RequesterAccountId");

            migrationBuilder.CreateIndex(
                name: "IX_tenant_requests_ReviewedBy",
                table: "tenant_requests",
                column: "ReviewedBy");

            migrationBuilder.CreateIndex(
                name: "IX_tenant_requests_Status",
                table: "tenant_requests",
                column: "Status");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "extension_services");

            migrationBuilder.DropTable(
                name: "tenant_requests");
        }
    }
}
