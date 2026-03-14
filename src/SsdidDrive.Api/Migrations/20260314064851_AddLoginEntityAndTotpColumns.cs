using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddLoginEntityAndTotpColumns : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "BackupCodes",
                table: "users",
                type: "text",
                nullable: true);

            migrationBuilder.AddColumn<bool>(
                name: "EmailVerified",
                table: "users",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<bool>(
                name: "TotpEnabled",
                table: "users",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "TotpSecret",
                table: "users",
                type: "text",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "logins",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    AccountId = table.Column<Guid>(type: "uuid", nullable: false),
                    Provider = table.Column<string>(type: "text", nullable: false),
                    ProviderSubject = table.Column<string>(type: "text", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()"),
                    LinkedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_logins", x => x.Id);
                    table.ForeignKey(
                        name: "FK_logins_users_AccountId",
                        column: x => x.AccountId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_logins_AccountId",
                table: "logins",
                column: "AccountId");

            migrationBuilder.CreateIndex(
                name: "IX_logins_Provider_ProviderSubject",
                table: "logins",
                columns: new[] { "Provider", "ProviderSubject" },
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "logins");

            migrationBuilder.DropColumn(
                name: "BackupCodes",
                table: "users");

            migrationBuilder.DropColumn(
                name: "EmailVerified",
                table: "users");

            migrationBuilder.DropColumn(
                name: "TotpEnabled",
                table: "users");

            migrationBuilder.DropColumn(
                name: "TotpSecret",
                table: "users");
        }
    }
}
