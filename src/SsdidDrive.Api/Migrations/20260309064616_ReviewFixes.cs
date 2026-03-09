using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace SsdidDrive.Api.Migrations
{
    /// <inheritdoc />
    public partial class ReviewFixes : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ApprovedBy",
                table: "recovery_requests");

            migrationBuilder.CreateTable(
                name: "recovery_approvals",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false, defaultValueSql: "gen_random_uuid()"),
                    RecoveryRequestId = table.Column<Guid>(type: "uuid", nullable: false),
                    TrusteeId = table.Column<Guid>(type: "uuid", nullable: false),
                    EncryptedShare = table.Column<byte[]>(type: "bytea", nullable: true),
                    ApprovedAt = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false, defaultValueSql: "now()")
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_recovery_approvals", x => x.Id);
                    table.ForeignKey(
                        name: "FK_recovery_approvals_recovery_requests_RecoveryRequestId",
                        column: x => x.RecoveryRequestId,
                        principalTable: "recovery_requests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_recovery_approvals_users_TrusteeId",
                        column: x => x.TrusteeId,
                        principalTable: "users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_recovery_shares_RecoveryConfigId_TrusteeId",
                table: "recovery_shares",
                columns: new[] { "RecoveryConfigId", "TrusteeId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_recovery_approvals_RecoveryRequestId_TrusteeId",
                table: "recovery_approvals",
                columns: new[] { "RecoveryRequestId", "TrusteeId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_recovery_approvals_TrusteeId",
                table: "recovery_approvals",
                column: "TrusteeId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "recovery_approvals");

            migrationBuilder.DropIndex(
                name: "IX_recovery_shares_RecoveryConfigId_TrusteeId",
                table: "recovery_shares");

            migrationBuilder.AddColumn<string>(
                name: "ApprovedBy",
                table: "recovery_requests",
                type: "character varying(2048)",
                maxLength: 2048,
                nullable: true);
        }
    }
}
